/**
 * Gestión del identificador de conversación para el contrato de n8n.
 *
 * Reglas del contrato:
 * - conversationId debe cumplir ^[A-Za-z0-9_-]{8,64}$
 * - Debe ser seguro y único por conversación.
 * - Se conserva mientras continúe la misma conversación (misma sesión/usuario).
 * - No se comparte entre usuarios distintos.
 * - Se limpia al cerrar sesión.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';

import { CONVERSATION_ID_RE } from './contract';

export { CONVERSATION_ID_RE };

const KEY_PREFIX = 'nebula.conversationId.';
const keyFor = (userId: string) => `${KEY_PREFIX}${userId}`;

function randomToken(bytes: number): string {
  // Preferir CSPRNG cuando esté disponible (web y Hermes con soporte de crypto).
  const g: any = globalThis as any;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let out = '';
  if (g?.crypto?.getRandomValues) {
    const buf = new Uint8Array(bytes);
    g.crypto.getRandomValues(buf);
    for (let i = 0; i < bytes; i += 1) out += alphabet[buf[i] % alphabet.length];
    return out;
  }
  // Fallback sin crypto: combina tiempo y varios segmentos aleatorios.
  const seed = `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}${Math.random()
    .toString(36)
    .slice(2)}`;
  for (let i = 0; i < bytes; i += 1) {
    const c = seed.charCodeAt(i % seed.length) ^ Math.floor(Math.random() * 61);
    out += alphabet[Math.abs(c) % alphabet.length];
  }
  return out;
}

export function generateConversationId(): string {
  // 'nebula_conv_' (12) + 24 chars => 36, dentro de [8,64] y conforme al regex.
  const id = `nebula_conv_${randomToken(24)}`;
  return CONVERSATION_ID_RE.test(id) ? id : `nebula_conv_${randomToken(24)}`;
}

/** Devuelve el id persistido del usuario o crea uno nuevo si no existe. */
export async function getOrCreateConversationId(userId: string): Promise<string> {
  try {
    const existing = await AsyncStorage.getItem(keyFor(userId));
    if (existing && CONVERSATION_ID_RE.test(existing)) return existing;
  } catch {
    // Si falla el almacenamiento, continúa generando uno nuevo en memoria.
  }
  const fresh = generateConversationId();
  try {
    await AsyncStorage.setItem(keyFor(userId), fresh);
  } catch {
    // No bloquear por un fallo de persistencia.
  }
  return fresh;
}

/** Inicia una conversación nueva (descarta la anterior del mismo usuario). */
export async function resetConversationId(userId: string): Promise<string> {
  const fresh = generateConversationId();
  try {
    await AsyncStorage.setItem(keyFor(userId), fresh);
  } catch {
    // Ignorar.
  }
  return fresh;
}

/** Limpia el estado de conversación del usuario (al cerrar sesión). */
export async function clearConversationId(userId: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(keyFor(userId));
  } catch {
    // Ignorar.
  }
}
