import { useCallback, useEffect, useState } from 'react';

import { CURRICULUM_PLAN } from '../data/curriculum';
import { fetchAcademicProfile, type RealProfile } from '../services/academic';
import { useSession } from '../session/SessionContext';

export type AcademicView =
  | { status: 'loading' }
  | { status: 'error'; message: string; reload: () => void }
  | { status: 'empty'; reload: () => void }
  | { status: 'example'; profile: RealProfile; reload: () => void }
  | { status: 'loaded'; profile: RealProfile; reload: () => void };

/**
 * Perfil académico EJEMPLO para la vista previa sin autenticación configurada.
 * Se identifica siempre como ejemplo; nunca se presenta como dato real.
 */
const EXAMPLE_PROFILE: RealProfile = {
  currentSemester: 6,
  declaredGpa: 4.3,
  approvedCredits: 86, // semestres 1–5 del plan (ejemplo coherente con la malla)
  pendingCredits: CURRICULUM_PLAN.totalCredits - 86,
  totalCredits: CURRICULUM_PLAN.totalCredits,
  history: [],
  programName: CURRICULUM_PLAN.program,
  planLabel: 'Plan histórico (9 semestres, 151 créditos) — EJEMPLO',
};

/**
 * Resuelve el perfil académico según el estado de sesión:
 * - Sin autenticación configurada: perfil de EJEMPLO claramente identificado.
 * - Autenticado: lee el perfil real de Supabase (cargado / vacío / error).
 */
export function useAcademicProfile(): AcademicView {
  const session = useSession();
  const authConfigured = session.authConfigured;
  const signedIn = session.status === 'signedIn';

  const [view, setView] = useState<AcademicView>(
    !authConfigured
      ? { status: 'example', profile: EXAMPLE_PROFILE, reload: () => {} }
      : { status: 'loading' },
  );

  const load = useCallback(() => {
    if (!authConfigured) {
      setView({ status: 'example', profile: EXAMPLE_PROFILE, reload: () => load() });
      return;
    }
    if (!signedIn) {
      setView({ status: 'empty', reload: () => load() });
      return;
    }
    setView({ status: 'loading' });
    fetchAcademicProfile().then((res) => {
      if (res.kind === 'loaded') setView({ status: 'loaded', profile: res.profile, reload: () => load() });
      else if (res.kind === 'empty') setView({ status: 'empty', reload: () => load() });
      else setView({ status: 'error', message: res.message, reload: () => load() });
    });
  }, [authConfigured, signedIn]);

  useEffect(() => {
    load();
  }, [load]);

  return view;
}
