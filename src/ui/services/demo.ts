/**
 * Responder de DEMOSTRACIÓN local del chat.
 *
 * Se usa mientras los workflows conversacionales de n8n están inactivos
 * (RAG_ENABLED=false). Genera orientación general basada en la malla curricular
 * de referencia, SIN inventar notas, registros del estudiante ni respuestas del
 * servidor real. Cada respuesta se marca como demo en la interfaz.
 */

import { CURRICULUM_PLAN, creditsForSemester, subjectsBySemester } from '../data/curriculum';
import type { SendOutcome } from '../types';

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

function semesterDetail(n: number): string {
  const subs = subjectsBySemester(n);
  if (subs.length === 0) return `No tengo el detalle del semestre ${n}.`;
  const list = subs.map((s) => `• ${s.name} (${s.credits} cr)`).join('\n');
  return `Semestre ${n} del plan de ${CURRICULUM_PLAN.program} (${creditsForSemester(
    n,
  )} créditos):\n${list}`;
}

function respond(input: string): string {
  const q = normalize(input);

  // Detectar número de semestre mencionado.
  const semMatch = q.match(/semestre\s*(\d+)/) || q.match(/\b([1-9])(?:er|do|to|mo|vo|no)?\s*sem/);
  if (semMatch) {
    const n = Number(semMatch[1]);
    if (n >= 1 && n <= CURRICULUM_PLAN.semesters) return semesterDetail(n);
  }

  if (/(hola|buenas|buenos dias|buenas tardes|saludos)/.test(q)) {
    return '¡Hola! Soy Nébula. Puedo orientarte sobre la malla de Ingeniería de Sistemas de la UNAB (9 semestres, 151 créditos), tu matrícula, estado académico, proyección y recomendaciones de estudio. ¿Qué necesitas?';
  }

  if (/(matricula|matricular|inscribir|inscripcion|asignaturas que)/.test(q)) {
    return 'Para la matrícula puedes revisar la pantalla "Matrícula", donde se listan asignaturas candidatas según tu avance. En modo demo muestro el plan de referencia; la matrícula real nunca se ejecuta desde aquí.';
  }

  if (/(promedio|estado academico|creditos|avance|notas)/.test(q)) {
    return 'Tu estado académico (promedio, créditos aprobados y pendientes, avance) se muestra en la pantalla "Estado". Con datos reales requiere sesión autenticada; en modo demo verás un perfil de ejemplo claramente identificado.';
  }

  if (/(proyeccion|escenario|cuando termino|graduar|semestres me faltan)/.test(q)) {
    return 'En "Proyección" puedes explorar escenarios de avance (por ejemplo, cuántos periodos faltarían según los créditos por semestre). Son estimaciones claramente identificadas, no promesas ni registros oficiales.';
  }

  if (/(recomend|deberia|consejo|que estudio|como estudiar|habito)/.test(q)) {
    return 'En "Recomendaciones" encontrarás orientación de estudio y sugerencias de ruta académica. Distingo entre orientación general y lo que requeriría datos verificados de tu historia académica.';
  }

  if (/(malla|pensum|plan de estudios|cuantos creditos|cuantos semestres)/.test(q)) {
    return `El plan de referencia es ${CURRICULUM_PLAN.program} de la ${CURRICULUM_PLAN.institution}: ${CURRICULUM_PLAN.semesters} semestres, ${CURRICULUM_PLAN.totalCredits} créditos y ${CURRICULUM_PLAN.totalSubjects} asignaturas. Pregúntame por un "semestre N" para ver su detalle.`;
  }

  if (/(iglesia|clima|futbol|chiste|amor)/.test(q)) {
    return 'Soy un asistente académico de la UNAB, así que me enfoco en tu plan de estudios, matrícula, estado académico y recomendaciones. ¿Te ayudo con alguno de esos temas?';
  }

  return 'Puedo orientarte sobre la malla de Ingeniería de Sistemas (pregúntame por un "semestre N"), matrícula, estado académico, proyección y recomendaciones. En este momento funciono en modo demostración, con orientación general y sin acceder a datos reales del estudiante.';
}

export async function sendToDemo(message: string): Promise<SendOutcome> {
  // Latencia simulada para que el estado "thinking" sea perceptible.
  const delay = 700 + Math.floor(Math.random() * 500);
  await new Promise((r) => setTimeout(r, delay));
  return { ok: true, reply: respond(message), demo: true };
}
