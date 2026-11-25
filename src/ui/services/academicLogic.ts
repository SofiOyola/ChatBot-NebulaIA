/**
 * Lógica PURA de presentación académica (sin dependencias de React Native ni de
 * Supabase), para poder probarla de forma aislada.
 */

export type NextSemesterPlan =
  | { kind: 'unknown' } // no conocemos el semestre actual
  | { kind: 'last' } // ya está en el último semestre; no hay "siguiente"
  | { kind: 'next'; nextSemester: number };

/**
 * Determina qué semestre debe mostrar "Matrícula": el SIGUIENTE al actual.
 * Si el estudiante está en el último semestre, no se genera uno adicional.
 */
export function nextSemesterPlan(currentSemester: number | null, maxSemesters = 9): NextSemesterPlan {
  if (currentSemester === null || !Number.isInteger(currentSemester)) return { kind: 'unknown' };
  if (currentSemester >= maxSemesters) return { kind: 'last' };
  return { kind: 'next', nextSemester: currentSemester + 1 };
}

export type CreditProgressInput = {
  verifiedApproved: number;
  reportedApproved: number;
  pending: number;
} | null;

/**
 * Deriva créditos aprobados/pendientes SOLO cuando existen registros reales.
 * Nunca se deducen del semestre actual. Si no hay datos, devuelve null (desconocido).
 */
export function deriveApprovedCredits(
  credits: CreditProgressInput,
  historyCount: number,
): { approved: number | null; pending: number | null } {
  if (!credits) return { approved: null, pending: null };
  const known = credits.verifiedApproved + credits.reportedApproved;
  if (historyCount > 0 && known > 0) {
    return { approved: known, pending: credits.pending };
  }
  return { approved: null, pending: null };
}
