/**
 * Cliente de Supabase Auth para el frontend.
 *
 * Usa únicamente la URL del proyecto y la clave ANÓNIMA pública (seguras para
 * cliente). La sesión se persiste con AsyncStorage (Android y web), se refresca
 * automáticamente y se puede restaurar al abrir la app. Si la configuración no
 * está disponible, `supabase` es null y la app usa modo demo.
 *
 * Nunca se imprimen ni exponen tokens ni contraseñas.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  createClient,
  type Session,
  type SupabaseClient,
  type User,
} from '@supabase/supabase-js';

import { AUTH_ENABLED, SUPABASE_ANON_KEY, SUPABASE_URL } from './config';

let client: SupabaseClient | null = null;

if (AUTH_ENABLED && SUPABASE_URL && SUPABASE_ANON_KEY) {
  client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      storage: AsyncStorage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  });
}

export const supabase = client;
export const isAuthConfigured = !!client;

export type { Session, User };

export type AuthResult = { ok: true } | { ok: false; message: string };

/** Traduce errores de Supabase Auth a mensajes claros en español. */
function translateAuthError(message: string): string {
  const m = message.toLowerCase();
  if (m.includes('invalid login credentials')) return 'Correo o contraseña incorrectos.';
  if (m.includes('email not confirmed')) return 'Debes confirmar tu correo antes de iniciar sesión.';
  if (m.includes('rate limit') || m.includes('too many')) return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
  if (m.includes('network') || m.includes('fetch')) return 'Sin conexión. Revisa tu red e inténtalo otra vez.';
  return message || 'No se pudo iniciar sesión.';
}

export async function signInWithPassword(email: string, password: string): Promise<AuthResult> {
  if (!supabase) return { ok: false, message: 'Autenticación no configurada (modo demo).' };
  try {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return { ok: false, message: translateAuthError(error.message) };
    return { ok: true };
  } catch {
    return { ok: false, message: 'Sin conexión con el servidor de autenticación.' };
  }
}

export async function signOut(): Promise<void> {
  if (!supabase) return;
  try {
    await supabase.auth.signOut();
  } catch {
    // Ignorar errores de red al cerrar sesión; la sesión local se limpia igualmente.
  }
}

export async function getCurrentSession(): Promise<Session | null> {
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  return data.session ?? null;
}

/** Devuelve un access token válido (lo refresca si es necesario). */
export async function getAccessToken(): Promise<string | null> {
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
}

/** Suscripción a cambios de sesión (login, logout, refresh, expiración). */
export function onAuthStateChange(cb: (session: Session | null) => void): () => void {
  if (!supabase) {
    cb(null);
    return () => {};
  }
  const { data } = supabase.auth.onAuthStateChange((_event, session) => cb(session));
  return () => data.subscription.unsubscribe();
}
