import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

import ScreenContainer from '../components/ScreenContainer';
import { Card, EmptyState, InfoBanner, LoadingState, Pill, ProgressBar, StatTile } from '../components/ui';
import { useAcademicProfile } from '../hooks/useAcademicProfile';
import type { RealProfile } from '../services/academic';
import { colors, spacing } from '../theme/theme';

export default function EstadoAcademicoScreen() {
  const view = useAcademicProfile();

  return (
    <ScreenContainer
      title="Estado académico"
      subtitle="Resumen de tu avance. Los datos declarados por el estudiante se identifican como tales."
    >
      {view.status === 'loading' ? <LoadingState label="Cargando tu perfil…" /> : null}

      {view.status === 'error' ? (
        <EmptyState
          title="No se pudo cargar tu estado académico"
          detail={view.message}
          actionLabel="Reintentar"
          onAction={view.reload}
        />
      ) : null}

      {view.status === 'empty' ? (
        <EmptyState
          title="Información académica no disponible"
          detail="Aún no hay un perfil académico registrado para tu cuenta. Cuando se registre tu semestre y promedio, aparecerán aquí con su procedencia."
          actionLabel="Actualizar"
          onAction={view.reload}
        />
      ) : null}

      {view.status === 'example' || view.status === 'loaded' ? (
        <ProfileBody profile={view.profile} isExample={view.status === 'example'} />
      ) : null}
    </ScreenContainer>
  );
}

function valueOrNA(v: number | null, fmt: (n: number) => string): string {
  return v === null ? 'No disp.' : fmt(v);
}

function ProfileBody({ profile, isExample }: { profile: RealProfile; isExample: boolean }) {
  const provenance = isExample ? 'ejemplo' : 'declarado';
  const creditsKnown = profile.approvedCredits !== null;
  const progressPct =
    creditsKnown && profile.totalCredits > 0
      ? Math.round(((profile.approvedCredits as number) / profile.totalCredits) * 100)
      : null;

  return (
    <View style={{ gap: spacing.md }}>
      {isExample ? (
        <InfoBanner tone="warn" text="Datos de EJEMPLO para vista previa. No corresponden a un estudiante real. Inicia sesión para ver tu perfil." />
      ) : (
        <InfoBanner text="Semestre y promedio son datos declarados por el estudiante, no una certificación oficial de la UNAB." />
      )}

      <View style={styles.statsRow}>
        <StatTile value={valueOrNA(profile.declaredGpa, (n) => n.toFixed(2))} label="Promedio" accent={colors.lavender} />
        <StatTile value={valueOrNA(profile.currentSemester, (n) => `${n}º`)} label="Semestre actual" accent={colors.cosmicBlue} />
      </View>
      <View style={styles.statsRow}>
        <StatTile value={valueOrNA(profile.approvedCredits, (n) => `${n}`)} label="Créditos aprobados" accent={colors.success} />
        <StatTile value={valueOrNA(profile.pendingCredits, (n) => `${n}`)} label="Créditos pendientes" accent={colors.warning} />
      </View>

      <Card>
        <View style={styles.rowBetween}>
          <Text style={styles.cardTitle}>Avance de carrera</Text>
          {progressPct !== null ? <Pill text={`${progressPct}%`} tone="ok" /> : <Pill text="sin datos" tone="warn" />}
        </View>
        {progressPct !== null ? (
          <>
            <ProgressBar pct={progressPct} />
            <Text style={styles.meta}>
              {profile.approvedCredits} de {profile.totalCredits} créditos del plan de 9 semestres.
            </Text>
          </>
        ) : (
          <Text style={styles.meta}>
            No conocemos los créditos aprobados, así que no se calcula el avance. No se deduce del semestre.
          </Text>
        )}
      </Card>

      <View style={styles.provRow}>
        <Pill text={`Promedio: ${provenance}`} tone={isExample ? 'warn' : 'info'} />
        <Pill text={`Semestre: ${provenance}`} tone={isExample ? 'warn' : 'info'} />
      </View>

      {profile.history.length > 0 ? (
        <Card>
          <Text style={styles.cardTitle}>Materias registradas ({profile.history.length})</Text>
          {profile.history.map((h) => (
            <View key={`${h.positionId}`} style={styles.histRow}>
              <View style={{ flex: 1 }}>
                <Text style={styles.name}>{h.courseName}</Text>
                <Text style={styles.meta}>Semestre {h.semester} · {h.credits} cr · {h.outcome}</Text>
              </View>
              {h.finalGrade !== null ? <Text style={styles.grade}>{h.finalGrade.toFixed(1)}</Text> : null}
            </View>
          ))}
        </Card>
      ) : !isExample ? (
        <Card>
          <Text style={styles.cardTitle}>Materias registradas</Text>
          <Text style={styles.meta}>Aún no hay materias registradas para tu cuenta.</Text>
        </Card>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  statsRow: { flexDirection: 'row', gap: spacing.md },
  cardTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '700' },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.md },
  provRow: { flexDirection: 'row', gap: spacing.sm, flexWrap: 'wrap' },
  meta: { color: colors.textMuted, fontSize: 12, marginTop: spacing.sm, lineHeight: 18 },
  histRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    gap: spacing.sm,
  },
  name: { color: colors.textPrimary, fontSize: 14, fontWeight: '600' },
  grade: { color: colors.success, fontSize: 16, fontWeight: '800' },
});
