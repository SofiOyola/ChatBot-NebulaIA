/**
 * Cliente conversacional del contrato REAL de n8n (sandbox Nébula 2.0).
 *
 * No se inventan URLs ni respuestas. La URL llega por EXPO_PUBLIC_N8N_WEBHOOK_URL.
 * Mientras el sandbox esté inactivo no hay envíos automáticos: solo se envía
 * cuando el usuario lo solicita explícitamente desde el chat.
 *
 * Solicitud:
 *   POST <webhook>
 *   Headers: Authorization: Bearer <supabase_access_token>, Content-Type: application/json
 *   Body: { "message": string(no vacío), "conversationId": ^[A-Za-z0-9_-]{8,64}$ }
 *
 * Respuesta 200:
 *   { "success": true, "project": "Nebula 2.0", "response": "<texto real>" }
 *   n8n puede envolver la respuesta en un array [ { ... } ]: se desenvuelve.
 *
 * Errores: 400 invalid_message | 400 invalid_conversation_id |
 *          401 unauthorized | 502 agent_unavailable | 404 (no escuchando) |
 *          HTML/no-JSON | red | timeout.
 *
 * Registro de desarrollo: SOLO metadatos seguros (estado HTTP, content-type,
 * código resuelto, duración). NUNCA se registran JWT, Authorization, contraseñas
 * ni datos personales.
 */

import { N8N_WEBHOOK_URL } from './config';
import { CONVERSATION_ID_RE, interpretResponse } from './contract';
import type { ChatErrorCode, SendOutcome } from '../types';

const TIMEOUT_MS = 30000;

const MESSAGES: Record<ChatErrorCode, string> = {
  invalid_message: 'El mensaje no es válido. Escribe una pregunta e inténtalo de nuevo.',
  invalid_conversation_id: 'La conversación no es válida. Se reiniciará; vuelve a intentarlo.',
  unauthorized: 'Tu sesión expiró o no es válida. Inicia sesión de nuevo.',
  agent_unavailable: 'Nébula no está disponible en este momento. Inténtalo de nuevo en unos segundos.',
  network: 'No se pudo conectar con el asistente. Revisa tu conexión e inténtalo otra vez.',
  timeout: 'La solicitud tardó demasiado. Inténtalo de nuevo.',
  bad_response: 'Respuesta inesperada del servidor. Inténtalo de nuevo.',
  not_found: 'El webhook no está activo. Publica el sandbox o activa "Listen for test event" en n8n.',
  not_configured: 'El asistente aún no está configurado.',
};

const RETRYABLE: Record<ChatErrorCode, boolean> = {
  invalid_message: false,
  invalid_conversation_id: true,
  unauthorized: false,
  agent_unavailable: true,
  network: true,
  timeout: true,
  bad_response: true,
  not_found: true,
  not_configured: false,
};

function fail(code: ChatErrorCode): SendOutcome {
  return { ok: false, code, message: MESSAGES[code], retryable: RETRYABLE[code] };
}

/** Log de desarrollo con metadatos no sensibles únicamente. */
function devLog(meta: { status?: number; contentType?: string; code?: ChatErrorCode; ms?: number }) {
  // __DEV__ es global en React Native/Expo.
  // eslint-disable-next-line no-undef
  if (typeof __DEV__ !== 'undefined' && __DEV__) {
    // No se incluyen cuerpos, tokens ni cabeceras: solo forma de la respuesta.
    console.log('[n8n]', JSON.stringify(meta));
  }
}

type N8nParams = {
  message: string;
  conversationId: string;
  accessToken: string | null;
};

export async function sendToN8n({ message, conversationId, accessToken }: N8nParams): Promise<SendOutcome> {
  if (!N8N_WEBHOOK_URL) return fail('not_configured');

  // Validación cliente conforme al contrato (evita viajes inútiles).
  const trimmed = message.trim();
  if (trimmed.length === 0) return fail('invalid_message');
  if (!CONVERSATION_ID_RE.test(conversationId)) return fail('invalid_conversation_id');
  // Sin sesión autenticada no se intenta una llamada real.
  if (!accessToken) return fail('unauthorized');

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  const started = Date.now();
  try {
    const res = await fetch(N8N_WEBHOOK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ message: trimmed, conversationId }),
      signal: controller.signal,
    });

    const contentType = res.headers.get('content-type') ?? '';
    const raw = await res.text();
    const ms = Date.now() - started;

    // Interpretación pura y testeable (desenvuelve arrays de n8n, HTML, errores).
    const result = interpretResponse(res.status, res.ok, contentType, raw);
    if (result.kind === 'ok') {
      devLog({ status: res.status, contentType, ms });
      return { ok: true, reply: result.reply, demo: false };
    }
    devLog({ status: res.status, contentType, code: result.code, ms });
    return fail(result.code);
  } catch (e: unknown) {
    const aborted = e instanceof Error && e.name === 'AbortError';
    devLog({ code: aborted ? 'timeout' : 'network', ms: Date.now() - started });
    return fail(aborted ? 'timeout' : 'network');
  } finally {
    clearTimeout(timer);
  }
}
