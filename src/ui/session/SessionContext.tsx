import React, { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react';

import { AUTH_ENABLED, CHAT_BACKEND_CONFIGURED } from '../services/config';
import {
  clearConversationId,
  getOrCreateConversationId,
  resetConversationId,
} from '../services/conversation';
import {
  getAccessToken as fetchAccessToken,
  getCurrentSession,
  isAuthConfigured,
  onAuthStateChange,
  signInWithPassword,
  signOut as supabaseSignOut,
  type AuthResult,
  type User,
} from '../services/supabase';

export type AuthStatus = 'loading' | 'signedOut' | 'signedIn';

/**
 * Estado del backend conversacional:
 * - unconfigured: no hay webhook configurado (chat en modo demo).
 * - ready: webhook configurado, aún sin verificar con una respuesta real.
 * - connecting: hay una solicitud real en curso.
 * - connected: se recibió una respuesta real válida (conexión verificada).
 * - error: la última solicitud real falló o el servicio no está disponible.
 */
export type BackendStatus = 'unconfigured' | 'ready' | 'connecting' | 'connected' | 'error';

type SessionState = {
  authConfigured: boolean;
  /** El chat real es posible (webhook configurado + sesión activa). */
  backendConfigured: boolean;
  status: AuthStatus;
  user: User | null;
  conversationId: string | null;
  /** Estado observable de la conexión con el backend conversacional. */
  backendStatus: BackendStatus;
  signIn: (email: string, password: string) => Promise<AuthResult>;
  signOut: () => Promise<void>;
  getAccessToken: () => Promise<string | null>;
  newConversation: () => Promise<void>;
  /** Reporta el resultado de una solicitud real (no se marca conectado a priori). */
  reportBackend: (status: 'connecting' | 'connected' | 'error') => void;
};

const SessionContext = createContext<SessionState | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>(isAuthConfigured ? 'loading' : 'signedOut');
  const [user, setUser] = useState<User | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const initialBackend: BackendStatus = CHAT_BACKEND_CONFIGURED ? 'ready' : 'unconfigured';
  const [backendStatus, setBackendStatus] = useState<BackendStatus>(initialBackend);
  const prevUserId = useRef<string | null>(null);

  useEffect(() => {
    if (!isAuthConfigured) return;
    let active = true;

    // Restaurar sesión existente al abrir la app.
    getCurrentSession().then((session) => {
      if (!active) return;
      applySession(session?.user ?? null);
    });

    // Reaccionar a login, logout, refresh y expiración de token.
    const unsub = onAuthStateChange((session) => {
      applySession(session?.user ?? null);
    });

    return () => {
      active = false;
      unsub();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function applySession(nextUser: User | null) {
    if (nextUser) {
      setUser(nextUser);
      setStatus('signedIn');
      if (prevUserId.current !== nextUser.id) {
        prevUserId.current = nextUser.id;
        getOrCreateConversationId(nextUser.id).then(setConversationId);
      }
    } else {
      // Limpieza al cerrar sesión / expirar.
      const gone = prevUserId.current;
      if (gone) clearConversationId(gone);
      prevUserId.current = null;
      setUser(null);
      setConversationId(null);
      setBackendStatus(initialBackend);
      setStatus('signedOut');
    }
  }

  const value = useMemo<SessionState>(
    () => ({
      authConfigured: AUTH_ENABLED && isAuthConfigured,
      backendConfigured: CHAT_BACKEND_CONFIGURED,
      status,
      user,
      conversationId,
      backendStatus,
      signIn: (email, password) => signInWithPassword(email, password),
      signOut: async () => {
        await supabaseSignOut();
        // onAuthStateChange hará la limpieza; forzamos estado inmediato por UX.
        applySession(null);
      },
      getAccessToken: fetchAccessToken,
      newConversation: async () => {
        if (!user) return;
        const fresh = await resetConversationId(user.id);
        setConversationId(fresh);
      },
      reportBackend: (s) => setBackendStatus(s),
    }),
    [status, user, conversationId, backendStatus],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionState {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useSession debe usarse dentro de <SessionProvider>');
  return ctx;
}
