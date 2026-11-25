/**
 * Configuración de entorno del cliente NébulaIA.
 *
 * Reglas de seguridad:
 * - El frontend SOLO puede leer variables públicas (prefijo EXPO_PUBLIC_).
 * - NUNCA se incluyen aquí claves de Gemini, service_role de Supabase ni
 *   credenciales de PostgreSQL. Esas viven exclusivamente en el servidor.
 * - La SUPABASE_ANON_KEY es, por diseño, una clave pública de cliente.
 *
 * Si falta la configuración de un servicio, la app opera en MODO DEMOSTRACIÓN
 * claramente identificado. El modo demo no se hace pasar por datos reales.
 */

type Env = Record<string, string | undefined>;
const env: Env = (typeof process !== 'undefined' && process.env ? process.env : {}) as Env;

const read = (key: string): string | undefined => {
  const v = env[key];
  return v && v.trim().length > 0 ? v.trim() : undefined;
};

/**
 * Proyecto Supabase de NébulaIA 2.0. La URL es pública (no es un secreto). Se
 * puede sobrescribir por entorno; la clave ANÓNIMA pública SIEMPRE llega por
 * variable de entorno (no se incrusta en el repositorio).
 */
const DEFAULT_SUPABASE_URL = 'https://icsekpkuheckfkgkqosg.supabase.co';

export const SUPABASE_URL = read('EXPO_PUBLIC_SUPABASE_URL') ?? DEFAULT_SUPABASE_URL;
export const SUPABASE_ANON_KEY = read('EXPO_PUBLIC_SUPABASE_ANON_KEY');

/**
 * Webhook del workflow conversacional de n8n (contrato real del sandbox).
 * - Prueba:     .../webhook-test/nebula-v2-rag-sandbox/chat  (requiere "Listen for test event")
 * - Producción: .../webhook/nebula-v2-rag-sandbox/chat       (aún no disponible)
 * Se configura explícitamente por entorno; no se incrusta ninguna URL por defecto.
 */
export const N8N_WEBHOOK_URL = read('EXPO_PUBLIC_N8N_WEBHOOK_URL');

/**
 * El chat real SOLO se intenta cuando hay un webhook configurado y está marcado
 * como habilitado. Esto NO significa "conectado": la conexión real únicamente se
 * confirma cuando el servicio responde correctamente (ver el cliente n8n).
 */
export const CHAT_BACKEND_CONFIGURED =
  read('EXPO_PUBLIC_CHAT_ENABLED') === 'true' && !!N8N_WEBHOOK_URL;

/** La autenticación requiere URL de proyecto + clave anónima pública. */
export const AUTH_ENABLED = !!SUPABASE_URL && !!SUPABASE_ANON_KEY;

export const APP_INFO = {
  name: 'NébulaIA',
  version: '2.0.0',
  university: 'Universidad Autónoma de Bucaramanga (UNAB)',
  program: 'Ingeniería de Sistemas',
};
