/**
 * Máquina de estados explícita del personaje Nébula.
 *
 * Estados: idle | thinking | talking
 *
 * Flujo normal:  idle -> (enviar) thinking -> (respuesta) talking -> idle
 * Flujo de error: idle -> (enviar) thinking -> (error) idle
 *
 * La animación se vincula a este estado real del chat, nunca a temporizadores
 * independientes que puedan desincronizarse.
 */

export type NebulaState = 'idle' | 'thinking' | 'talking';

export type NebulaEvent =
  | 'SEND' // el usuario envía una pregunta
  | 'RESPONSE' // llegó la respuesta del servidor
  | 'PRESENTED' // terminó la aparición progresiva del mensaje
  | 'ERROR'; // la solicitud falló

/**
 * Transición pura. Devuelve el siguiente estado dado el actual y un evento.
 * Las transiciones inválidas se ignoran (se mantiene el estado actual),
 * evitando saltos incorrectos si el usuario intenta enviar varias preguntas.
 */
export function nebulaTransition(state: NebulaState, event: NebulaEvent): NebulaState {
  switch (state) {
    case 'idle':
      return event === 'SEND' ? 'thinking' : 'idle';
    case 'thinking':
      if (event === 'RESPONSE') return 'talking';
      if (event === 'ERROR') return 'idle';
      return 'thinking';
    case 'talking':
      // Al terminar de presentar el mensaje regresa automáticamente a idle.
      if (event === 'PRESENTED') return 'idle';
      if (event === 'ERROR') return 'idle';
      return 'talking';
    default:
      return 'idle';
  }
}

/** Indica si se puede enviar una nueva pregunta (evita solicitudes duplicadas). */
export function canSend(state: NebulaState): boolean {
  return state === 'idle';
}
