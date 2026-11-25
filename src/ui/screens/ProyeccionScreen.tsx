import React, { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import ScreenContainer from '../components/ScreenContainer';
import { Card, EmptyState, InfoBanner, LoadingState, Pill, StatTile } from '../components/ui';
import { useAcademicProfile } from '../hooks/useAcademicProfile';
import type { RealProfile } from '../services/academic';
import { colors, radius, spacing } from '../theme/theme';

const MIN_CPS = 9;
const MAX_CPS = 21;

export default function ProyeccionScreen() {
  const view = useAcademicProfile();

  return (
    <ScreenContainer
      title="Proyección académica"
      subtitle="Estimaciones orientativas, no registros oficiales ni promesas de graduación."
    >
      {view.status === 'loading' ? <LoadingState label="Cargando tu perfil…" /> : null}
      {view.status === 'error' ? (
        <EmptyState title="No se pudo cargar la proyección" detail={view.message} actionLabel="Reintentar" onAction={view.reload} />
      ) : null}
      {view.status === 'empty' ? (
        <EmptyState
          title="Información académica no disponible"
          detail="Necesitamos tus créditos aprobados para proyectar tu avance. Cuando existan registros, verás la estimación aquí."
          actionLabel="Actualizar"
          onAction={view.reload}
        />
      ) : null}
      {view.status === 'example' || view.status === 'loaded' ? (
        <Projection profile={view.profile} isExample={view.status === 'example'} />
      ) : null}
    </ScreenContainer>
  );
}

function Projection({ profile, isExample }: { profile: RealProfile; isExample: boolean }) {
  const [creditsPerSem, setCreditsPerSem] = useState(16);
  const pending = profile.pendingCredits;
  const canEstimate = pending !== null && profile.approvedCredits !== null;

  const remainingSemesters = canEstimate ? Math.ceil((pending as number) / creditsPerSem) : null;
  const yearsApprox = remainingSemesters !== null ? Math.round((remainingSemesters / 2) * 10) / 10 : null;

  const dec = () => setCreditsPerSem((c) => Math.max(MIN_CPS, c - 1));
  const inc = () => setCreditsPerSem((c) => Math.min(MAX_CPS, c + 1));

  return (
    <View style={{ gap: spacing.md }}>
      {isExample ? (
        <InfoBanner tone="warn" text="Datos de EJEMPLO. No corresponden a un estudiante real." />
      ) : null}

      {!canEstimate ? (
        <Card>
          <Text style={styles.cardTitle}>Estimación no disponible</Text>
          <Text style={styles.body}>
            No conocemos tus créditos realmente aprobados, así que no estimamos los semestres restantes. No se
            deducen del semestre actual. Cuando se registren créditos aprobados, la proyección aparecerá aquí.
          </Text>
        </Card>
      ) : (
        <>
          <Card>
            <Text style={styles.cardTitle}>Escenario: créditos por semestre</Text>
            <View style={styles.stepper}>
              <Pressable onPress={dec} style={styles.stepBtn} accessibilityLabel="Disminuir créditos">
                <Text style={styles.stepTxt}>−</Text>
              </Pressable>
              <View style={styles.stepValue}>
                <Text style={styles.stepNumber}>{creditsPerSem}</Text>
                <Text style={styles.stepLabel}>créditos / semestre</Text>
              </View>
              <Pressable onPress={inc} style={styles.stepBtn} accessibilityLabel="Aumentar créditos">
                <Text style={styles.stepTxt}>+</Text>
              </Pressable>
            </View>
          </Card>

          <View style={styles.statsRow}>
            <StatTile value={`${remainingSemesters}`} label="Semestres restantes (est.)" accent={colors.cosmicBlue} />
            <StatTile value={`≈ ${yearsApprox}`} label="Años aprox. (est.)" accent={colors.lavender} />
          </View>

          <Card>
            <View style={styles.rowBetween}>
              <Text style={styles.body}>Créditos pendientes</Text>
              <Pill text={`${pending} cr`} tone="warn" />
            </View>
            <View style={styles.rowBetween}>
              <Text style={styles.body}>Créditos aprobados</Text>
              <Pill text={`${profile.approvedCredits} cr`} tone="ok" />
            </View>
            <View style={styles.rowBetween}>
              <Text style={styles.body}>Total del plan</Text>
              <Pill text={`${profile.totalCredits} cr`} tone="info" />
            </View>
          </Card>

          <Text style={styles.note}>
            Estimación = techo de (créditos pendientes ÷ créditos por semestre). No considera prerrequisitos,
            electivas específicas ni disponibilidad de cursos.
          </Text>
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  cardTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '700', marginBottom: spacing.md },
  stepper: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.md },
  stepBtn: {
    width: 52,
    height: 52,
    borderRadius: 52,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepTxt: { color: colors.softWhite, fontSize: 26, fontWeight: '700' },
  stepValue: { alignItems: 'center', flex: 1 },
  stepNumber: { color: colors.lavender, fontSize: 34, fontWeight: '900' },
  stepLabel: { color: colors.textMuted, fontSize: 12 },
  statsRow: { flexDirection: 'row', gap: spacing.md },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 8 },
  body: { color: colors.textSecondary, fontSize: 14 },
  note: { color: colors.textMuted, fontSize: 12, lineHeight: 18, fontStyle: 'italic' },
});
