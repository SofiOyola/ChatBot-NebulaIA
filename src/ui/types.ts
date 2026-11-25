/** Tipos compartidos de la aplicación. */

export type ChatRole = 'user' | 'assistant';

export type ChatMessage = {
  id: string;
  role: ChatRole;
  text: string;
  /** True si el contenido proviene del modo demostración local. */
  demo?: boolean;
  createdAt: number;
};

/** Códigos de error del contrato real de n8n (más los del transporte). */
export type ChatErrorCode =
  | 'invalid_message'
  | 'invalid_conversation_id'
  | 'unauthorized'
  | 'agent_unavailable'
  | 'network'
  | 'timeout'
  | 'bad_response'
  | 'not_found'
  | 'not_configured';

export type SendOutcome =
  | { ok: true; reply: string; demo: boolean }
  | { ok: false; message: string; code: ChatErrorCode; retryable: boolean };
