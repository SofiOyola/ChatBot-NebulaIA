/**
 * Lectura del perfil académico real del usuario autenticado desde Supabase.
 *
 * Usa EXCLUSIVAMENTE funciones SECURITY DEFINER del esquema public, que resuelven
 * la identidad desde el JWT (auth.uid()) y respetan el aislamiento por estudiante:
 *   - public.get_student_profile()  (nueva: semestre y promedio declarados)
 *   - public.get_credit_progress()  (créditos verificados/declarados/pendientes)
 *   - public.get_academic_history() (intentos por asignatura)
 *
 * No accede a tablas del esquema student directamente (está revocado para
 * authenticated). No inventa datos: si no hay registros, devuelve null.
 */

import { deriveApprovedCredits } from './academicLogic';
import { supabase } from './supabase';
import { CURRICULUM_PLAN } from '../data/curriculum';

export type CreditProgress = {
  total: number;
  verifiedApproved: number;
  reportedApproved: number;
  pending: number;
};

export type HistoryItem = {
  positionId: string;
  courseName: string;
  semester: number;
  credits: number;
  finalGrade: number | null;
  outcome: string;
  sourceType: string;
};

export type RealProfile = {
  currentSemester: number | null;
  /** Promedio declarado por el estudiante (no certificación oficial). */
  declaredGpa: number | null;
  /** Créditos aprobados conocidos (verificados + declarados). null si se desconocen. */
  approvedCredits: number | null;
  /** Créditos pendientes. null si se desconocen los aprobados. */
  pendingCredits: number | null;
  totalCredits: number;
  history: HistoryItem[];
  programName: string;
  planLabel: string;
};

export type ProfileFetch =
  | { kind: 'loaded'; profile: RealProfile }
  | { kind: 'empty' } // autenticado, sin perfil registrado (o función aún no desplegada)
  | { kind: 'error'; message: string };

const PLAN_LABEL = 'Plan histórico (9 semestres, 151 créditos)';

/** True si el error de PostgREST indica que la función/relación aún no existe. */
function isMissingObject(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false;
  const code = error.code ?? '';
  // PGRST202: función no encontrada en el esquema expuesto. 42883/42P01: no existe.
  return code === 'PGRST202' || code === '42883' || code === '42P01';
}

export async function fetchAcademicProfile(): Promise<ProfileFetch> {
  if (!supabase) return { kind: 'empty' };

  try {
    const profileRes = await supabase.rpc('get_student_profile');
    // Si la función aún no está desplegada, tratamos como "no disponible".
    if (profileRes.error && !isMissingObject(profileRes.error)) {
      return { kind: 'error', message: 'No se pudo leer el perfil académico.' };
    }
    const rows = (profileRes.data as unknown[]) ?? [];
    const row = Array.isArray(rows) && rows.length > 0 ? (rows[0] as Record<string, unknown>) : null;
    if (!row) return { kind: 'empty' };

    const currentSemester = toIntOrNull(row.current_semester);
    const declaredGpa = toNumOrNull(row.declared_cumulative_gpa);

    const [credits, history] = await Promise.all([fetchCreditProgress(), fetchHistory()]);

    // Solo afirmamos créditos aprobados si hay registros reales; no se deducen del semestre.
    const { approved: approvedCredits, pending: pendingCredits } = deriveApprovedCredits(
      credits,
      history.length,
    );

    return {
      kind: 'loaded',
      profile: {
        currentSemester,
        declaredGpa,
        approvedCredits,
        pendingCredits,
        totalCredits: CURRICULUM_PLAN.totalCredits,
        history,
        programName: CURRICULUM_PLAN.program,
        planLabel: PLAN_LABEL,
      },
    };
  } catch {
    return { kind: 'error', message: 'No se pudo conectar para leer el perfil.' };
  }
}

async function fetchCreditProgress(): Promise<CreditProgress | null> {
  if (!supabase) return null;
  const res = await supabase.rpc('get_credit_progress');
  if (res.error) return null;
  const rows = (res.data as unknown[]) ?? [];
  const r = Array.isArray(rows) && rows.length > 0 ? (rows[0] as Record<string, unknown>) : null;
  if (!r) return null;
  return {
    total: toInt(r.total_curriculum_credits),
    verifiedApproved: toInt(r.verified_approved_credits),
    reportedApproved: toInt(r.reported_only_approved_credits),
    pending: toInt(r.pending_or_unverified_credits),
  };
}

async function fetchHistory(): Promise<HistoryItem[]> {
  if (!supabase) return [];
  const res = await supabase.rpc('get_academic_history');
  if (res.error || !Array.isArray(res.data)) return [];
  return (res.data as Record<string, unknown>[]).map((r) => ({
    positionId: String(r.position_id ?? ''),
    courseName: String(r.course_name ?? ''),
    semester: toInt(r.curriculum_semester),
    credits: toInt(r.credits),
    finalGrade: toNumOrNull(r.final_grade),
    outcome: String(r.outcome ?? 'unknown'),
    sourceType: String(r.source_type ?? 'unknown'),
  }));
}

function toInt(v: unknown): number {
  const n = typeof v === 'string' ? parseInt(v, 10) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) ? n : 0;
}
function toIntOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'string' ? parseInt(v, 10) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) ? n : null;
}
function toNumOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'string' ? parseFloat(v) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) ? n : null;
}
