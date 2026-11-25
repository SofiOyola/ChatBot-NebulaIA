import { useCallback, useRef, useState } from 'react';

import { sendToDemo } from '../services/demo';
import { sendToN8n } from '../services/n8n';
import { useSession } from '../session/SessionContext';
import { canSend as canSendFor, nebulaTransition, type NebulaState } from '../state/nebulaState';
import type { ChatErrorCode, ChatMessage, SendOutcome } from '../types';

const WELCOME =
  '¡Hola! Soy Nébula, tu asistente académico de la UNAB. ¿En qué puedo ayudarte hoy?';

function uid(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function revealDurationFor(text: string): number {
  // Aparición progresiva: ~22 ms por caracter, acotada para que no se eternice.
  return Math.min(3200, Math.max(700, text.length * 22));
}

export type NebulaChat = {
  messages: ChatMessage[];
  nebulaState: NebulaState;
  error: string | null;
  errorCode: ChatErrorCode | null;
  errorRetryable: boolean;
  /** True cuando el chat opera en modo demostración local. */
  isDemo: boolean;
  canSend: boolean;
  revealId: string | null;
  revealMs: number;
  send: (text: string) => void;
  retry: () => void;
  dismissError: () => void;
};

export function useNebulaChat(): NebulaChat {
  const session = useSession();
  // Modo conectado: sesión autenticada + webhook configurado.
  const isReal = session.status === 'signedIn' && session.backendConfigured;
  const isDemo = !isReal;

  const [messages, setMessages] = useState<ChatMessage[]>([
    { id: 'welcome', role: 'assistant', text: WELCOME, createdAt: Date.now(), demo: isDemo },
  ]);
  const [nebulaState, setNebulaState] = useState<NebulaState>('idle');
  const [error, setError] = useState<string | null>(null);
  const [errorCode, setErrorCode] = useState<ChatErrorCode | null>(null);
  const [errorRetryable, setErrorRetryable] = useState(false);
  const [revealId, setRevealId] = useState<string | null>(null);
  const [revealMs, setRevealMs] = useState<number>(0);

  const busyRef = useRef(false); // evita solicitudes duplicadas
  const revealTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastMessage = useRef<string | null>(null);

  const runTransport = useCallback(
    async (text: string): Promise<SendOutcome> => {
      if (!isReal) return sendToDemo(text);
      const accessToken = await session.getAccessToken();
      const conversationId = session.conversationId ?? '';
      return sendToN8n({ message: text, conversationId, accessToken });
    },
    [isReal, session],
  );

  const dispatchSend = useCallback(
    (text: string, isRetry: boolean) => {
      const clean = text.trim();
      if (!clean) return;
      if (busyRef.current || !canSendFor('idle')) return;

      busyRef.current = true;
      setError(null);
      setErrorCode(null);
      lastMessage.current = clean;

      if (!isRetry) {
        const userMsg: ChatMessage = { id: uid(), role: 'user', text: clean, createdAt: Date.now() };
        setMessages((prev) => [...prev, userMsg]);
      }

      // idle -> thinking
      setNebulaState((s) => nebulaTransition(s, 'SEND'));
      if (isReal) session.reportBackend('connecting');

      runTransport(clean)
        .then((outcome) => {
          if (!outcome.ok) {
            // thinking -> idle (error). NO se sustituye por una respuesta local.
            setNebulaState((s) => nebulaTransition(s, 'ERROR'));
            setError(outcome.message);
            setErrorCode(outcome.code);
            setErrorRetryable(outcome.retryable);
            if (isReal) session.reportBackend('error');
            busyRef.current = false;
            return;
          }
          if (isReal) session.reportBackend('connected');
          const reply: ChatMessage = {
            id: uid(),
            role: 'assistant',
            text: outcome.reply,
            demo: outcome.demo,
            createdAt: Date.now(),
          };
          const ms = revealDurationFor(outcome.reply);
          setMessages((prev) => [...prev, reply]);
          setRevealId(reply.id);
          setRevealMs(ms);
          // thinking -> talking
          setNebulaState((s) => nebulaTransition(s, 'RESPONSE'));
          lastMessage.current = null;

          if (revealTimer.current) clearTimeout(revealTimer.current);
          revealTimer.current = setTimeout(() => {
            // talking -> idle al terminar la presentación progresiva
            setRevealId(null);
            setNebulaState((s) => nebulaTransition(s, 'PRESENTED'));
            busyRef.current = false;
          }, ms);
        })
        .catch(() => {
          setNebulaState((s) => nebulaTransition(s, 'ERROR'));
          setError('Ocurrió un error inesperado.');
          setErrorCode('bad_response');
          setErrorRetryable(true);
          if (isReal) session.reportBackend('error');
          busyRef.current = false;
        });
    },
    [isReal, runTransport, session],
  );

  const send = useCallback((text: string) => dispatchSend(text, false), [dispatchSend]);
  const retry = useCallback(() => {
    if (lastMessage.current) dispatchSend(lastMessage.current, true);
  }, [dispatchSend]);

  const dismissError = useCallback(() => {
    setError(null);
    setErrorCode(null);
  }, []);

  return {
    messages,
    nebulaState,
    error,
    errorCode,
    errorRetryable,
    isDemo,
    canSend: nebulaState === 'idle' && !busyRef.current,
    revealId,
    revealMs,
    send,
    retry,
    dismissError,
  };
}
