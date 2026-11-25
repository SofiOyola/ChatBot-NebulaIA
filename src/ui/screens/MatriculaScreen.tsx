import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

import ScreenContainer from '../components/ScreenContainer';
import { Card, EmptyState, InfoBanner, LoadingState, Pill } from '../components/ui';
import { CURRICULUM_PLAN, creditsForSemester, subjectsBySemester, type Subject } from '../data/curriculum';
import { useAcademicProfile } from '../hooks/useAcademicProfile';
import { nextSemesterPlan } from '../services/academicLogic';
import { colors, spacing } from '../theme/theme';

export default function MatriculaScreen() {
  const view = useAcademicProfile();

  return (
    <ScreenContainer
      title="Matrícula"
      subtitle="Asignaturas del próximo semestre según tu plan. No es una matrícula oficialmente autorizada."
    >
      {view.status === 'loading' ? <LoadingState label="Cargando tu perfil…" /> : null}
      {view.status === 'error' ? (
        <EmptyState title="No se pudo cargar la matrícula" detail={view.message} actionLabel="Reintentar" onAction={view.reload} />
      ) : null}
      {view.status === 'empty' ? (
        <EmptyState
          title="Información académica no disponible"
          detail="Necesitamos conocer tu semestre actual para mostrar las asignaturas del siguiente. Cuando se registre tu perfil, aparecerán aquí."
          actionLabel="Actualizar"
          onAction={view.reload}
        />
      ) : null}
      {view.status === 'example' || view.status === 'loaded' ? (
        <Body currentSemester={view.profile.currentSemester} isExample={view.status === 'example'} />
      ) : null}
    </ScreenContainer>
  );
}

function Body({ currentSemester, isExample }: { currentSemester: number | null; isExample: boolean }) {
  const plan = nextSemesterPlan(currentSemester, CURRICULUM_PLAN.semesters);

  if (plan.kind === 'unknown') {
    return (
      <EmptyState
        title="Semestre no registrado"
        detail="No conocemos tu semestre actual, así que no podemos indicar el siguiente. No se asume un valor."
      />
    );
  }

  // Noveno semestre: no existe un semestre 10 en la malla de 9 semestres.
  if (plan.kind === 'last') {
    return (
      <View style={{ gap: spacing.md }}>
        {isExample ? <InfoBanner tone="warn" text="Datos de EJEMPLO. No corresponden a un estudiante real." /> : null}
        <Card>
          <Text style={styles.cardTitle}>Estás en el último semestre</Text>
          <Text style={styles.body}>
            Cursas noveno semestre, el último del plan de {CURRICULUM_PLAN.semesters} semestres. No hay un semestre
            10 que matricular. Revisa con tu programa los requisitos de grado y trámites finales.
          </Text>
        </Card>
      </View>
    );
  }

  const nextSemester = plan.nextSemester;
  const subjects = subjectsBySemester(nextSemester);
  const credits = creditsForSemester(nextSemester);

  return (
    <View style={{ gap: spacing.md }}>
      {isExample ? (
        <InfoBanner tone="warn" text="Datos de EJEMPLO. No corresponden a un estudiante real." />
      ) : (
        <InfoBanner text={`Estás en ${currentSemester}º. A continuación, las asignaturas del próximo semestre (${nextSemester}º) según el plan. No es una matrícula autorizada.`} />
      )}

      <Card>
        <View style={styles.blockHeader}>
          <Text style={styles.cardTitle}>Asignaturas del {nextSemester}º semestre</Text>
          <Pill text={`${credits} cr`} tone="info" />
        </View>
        {subjects.map((s: Subject) => (
          <View key={s.id} style={styles.subjectRow}>
            <View style={{ flex: 1 }}>
              <Text style={styles.subjectName}>{s.name}</Text>
              <Text style={styles.subjectMeta}>
                {s.id} · {s.credits} crédito{s.credits === 1 ? '' : 's'}
              </Text>
            </View>
            <Pill text="próximo semestre" tone="neutral" />
          </View>
        ))}
      </Card>

      <Text style={styles.note}>
        La elegibilidad real depende de prerrequisitos y de tu historia académica verificada. La inscripción
        oficial se realiza en los canales de la UNAB; Nébula solo orienta.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  cardTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '700' },
  body: { color: colors.textSecondary, fontSize: 14, lineHeight: 20 },
  blockHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  subjectRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  subjectName: { color: colors.textPrimary, fontSize: 14, fontWeight: '600' },
  subjectMeta: { color: colors.textMuted, fontSize: 12, marginTop: 2 },
  note: { color: colors.textMuted, fontSize: 12, lineHeight: 18, fontStyle: 'italic' },
});
