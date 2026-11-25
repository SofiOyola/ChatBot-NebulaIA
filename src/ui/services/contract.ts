/**
 * Lógica PURA del contrato de n8n (sin dependencias de React Native).
 *
 * Aísla la interpretación de la respuesta HTTP para poder probarla de forma
 * aislada con respuestas simuladas (200/400/401/404/502, HTML, arrays de n8n).
 */

import type { ChatErrorCode } from '../types';

export const CONVERSATION_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;

export type Interpreted = { kind: 'ok'; reply: string } | { kind: 'error'; code: ChatErrorCode };

export function mapErrorStatus(status: number, bodyError?: string): ChatErrorCode {
  const e = (bodyError ?? '').toLowerCase();
  if (e.includes('invalid_message')) return 'invalid_message';
  if (e.includes('invalid_conversation_id')) return 'invalid_conversation_id';
  if (e.includes('unauthorized')) return 'unauthorized';
  if (e.includes('agent_unavailable')) return 'agent_unavailable';
  if (status === 400) return 'invalid_message';
  if (status === 401 || status === 403) return 'unauthorized';
  if (status === 404) return 'not_found';
  if (status === 502 || status === 503 || status === 504) return 'agent_unavailable';
  return 'bad_response';
}

/** Desenvuelve el objeto real, tolerando el array o el envoltorio json de n8n. */
export function unwrap(data: unknown): Record<string, unknown> | null {
  let d: unknown = data;
  for (let i = 0; i < 3; i += 1) {
    if (Array.isArray(d)) {
      d = d.length > 0 ? d[0] : null;
      continue;
    }
    if (d && typeof d === 'object') {
      const o = d as Record<string, unknown>;
      if ('json' in o && o.json && typeof o.json === 'object') {
        d = o.json;
        continue;
      }
      return o;
    }
    return null;
  }
  return d && typeof d === 'object' && !Array.isArray(d) ? (d as Record<string, unknown>) : null;
}

/** Extrae el texto de respuesta de la forma del contrato (con tolerancia). */
export function extractResponse(obj: Record<string, unknown>): string | null {
  for (const key of ['response', 'output', 'text', 'answer', 'message']) {
    const v = obj[key];
    if (typeof v === 'string' && v.trim()) return v;
  }
  return null;
}

function safeParse(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

/**
 * Interpreta una respuesta HTTP del webhook según el contrato real.
 * `ok` es res.ok (2xx). `contentType` y `rawText` provienen de la respuesta.
 */
export function interpretResponse(
  status: number,
  ok: boolean,
  contentType: string,
  rawText: string,
): Interpreted {
  const ct = (contentType ?? '').toLowerCase();
  const looksJson = ct.includes('application/json') || /^\s*[[{]/.test(rawText);
  const data = looksJson ? safeParse(rawText) : null;

  if (!ok) {
    const obj = unwrap(data);
    const bodyError =
      obj && typeof obj.error === 'string'
        ? obj.error
        : obj && typeof obj.message === 'string'
          ? obj.message
          : undefined;
    return { kind: 'error', code: mapErrorStatus(status, bodyError) };
  }

  // 200 pero no es JSON (HTML de túnel, página de error, etc.).
  if (data === null) return { kind: 'error', code: 'bad_response' };

  const obj = unwrap(data);
  if (obj) {
    if (obj.success === false) {
      const code = mapErrorStatus(status, typeof obj.error === 'string' ? obj.error : undefined);
      return { kind: 'error', code: code === 'bad_response' ? 'agent_unavailable' : code };
    }
    const reply = extractResponse(obj);
    if (reply) return { kind: 'ok', reply };
  }
  return { kind: 'error', code: 'bad_response' };
}
