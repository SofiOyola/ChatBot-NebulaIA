import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

import ScreenContainer from '../components/ScreenContainer';
import { Card, Pill } from '../components/ui';
import { useAcademicProfile } from '../hooks/useAcademicProfile';
import { colors, spacing } from '../theme/theme';

type Rec = { title: string; detail: string; kind: 'general' | 'datos' };

const GENERAL: Rec[] = [
  {
    title: 'Planifica tu carga por créditos',
    detail:
      'Equilibra asignaturas teóricas y prácticas en cada periodo. Para materias de 3+ créditos, reserva bloques de estudio semanales constantes.',
    kind: 'general',
  },
  {
    title: 'Prioriza prerrequisitos de la línea de software',
    detail:
      'Fundamentos de programación, Estructura de datos e Ingeniería de software forman una ruta encadenada. Avanzar ordenadamente evita cuellos de botella.',
    kind: 'general',
  },
  {
    title: 'Aprovecha las electivas de profundización',
    detail:
      'El plan incluye varias electivas de profundización. Alinéalas con tu interés (datos, ciberseguridad, IoT) para dar coherencia a tu perfil.',
    kind: 'general',
  },
  {
    title: 'Técnicas de estudio activo',
    detail:
      'Usa repaso espaciado y práctica deliberada, especialmente en Cálculo, Matemáticas computacionales e Investigación de operaciones.',
    kind: 'general',
  },
];

export default function RecomendacionesScreen() {
  const view = useAcademicProfile();

  // Ruta según avance: solo se personaliza con datos; de lo contrario, general o ejemplo.
  let routeTag: { text: string; tone: 'info' | 'warn' | 'ok' } = { text: 'general', tone: 'info' };
  let routeText =
    'La ruta personalizada requiere tu semestre y créditos registrados. Mientras tanto, prioriza la línea de software y las matemáticas del plan.';
  if (view.status === 'example') {
    routeTag = { text: 'ejemplo', tone: 'warn' };
    routeText = `Con el perfil de EJEMPLO (semestre ${view.profile.currentSemester ?? '—'}), convendría afianzar la línea de software antes de las electivas avanzadas. Ilustrativo; con datos reales se personaliza.`;
  } else if (view.status === 'loaded' && view.profile.currentSemester !== null) {
    routeTag = { text: 'según tu semestre', tone: 'ok' };
    const next = Math.min(view.profile.currentSemester + 1, 9);
    routeText = `Estás en ${view.profile.currentSemester}º. De cara al ${next}º, revisa en "Matrícula" las asignaturas del próximo semestre y asegúrate de los prerrequisitos de la línea de software.`;
  }

  return (
    <ScreenContainer
      title="Recomendaciones"
      subtitle="Orientación académica y de estudio. Se distingue la orientación general de lo que requeriría datos verificados."
    >
      <Card>
        <View style={styles.legendRow}>
          <Pill text="orientación general" tone="info" />
          <Pill text="requiere datos verificados" tone="warn" />
        </View>
        <Text style={styles.body}>
          Las sugerencias generales aplican a cualquier estudiante del plan. Las recomendaciones
          basadas en datos (tu historia, notas y prerrequisitos) solo son fiables con sesión
          autenticada y backend conectado.
        </Text>
      </Card>

      {GENERAL.map((r) => (
        <Card key={r.title}>
          <View style={styles.cardHeader}>
            <Text style={styles.cardTitle}>{r.title}</Text>
            <Pill text="general" tone="info" />
          </View>
          <Text style={styles.body}>{r.detail}</Text>
        </Card>
      ))}

      <Card>
        <View style={styles.cardHeader}>
          <Text style={styles.cardTitle}>Ruta sugerida según tu avance</Text>
          <Pill text={routeTag.text} tone={routeTag.tone} />
        </View>
        <Text style={styles.body}>{routeText}</Text>
      </Card>

      <Text style={styles.note}>
        Nébula ofrece orientación; las decisiones académicas oficiales se confirman con tu programa y
        el reglamento estudiantil de la UNAB.
      </Text>
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  legendRow: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.sm, flexWrap: 'wrap' },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.xs,
    gap: spacing.sm,
  },
  cardTitle: { color: colors.textPrimary, fontSize: 15, fontWeight: '700', flex: 1 },
  body: { color: colors.textSecondary, fontSize: 14, lineHeight: 20 },
  note: { color: colors.textMuted, fontSize: 12, lineHeight: 18, fontStyle: 'italic' },
});
