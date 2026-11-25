import { LinearGradient } from 'expo-linear-gradient';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type KeyboardTypeOptions,
  type StyleProp,
  type ViewStyle,
} from 'react-native';

import { colors, gradients, radius, shadow, spacing, typography } from '../theme/theme';

/* ------------------------- Estados: carga / vacío ------------------------- */

export function LoadingState({ label = 'Cargando…' }: { label?: string }) {
  return (
    <View style={styles.stateBox}>
      <ActivityIndicator color={colors.lavender} />
      <Text style={styles.stateText}>{label}</Text>
    </View>
  );
}

export function EmptyState({
  title,
  detail,
  actionLabel,
  onAction,
}: {
  title: string;
  detail?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <View style={styles.stateBox}>
      <Text style={styles.emptyTitle}>{title}</Text>
      {detail ? <Text style={styles.stateText}>{detail}</Text> : null}
      {actionLabel && onAction ? (
        <Pressable onPress={onAction} style={styles.stateAction} accessibilityRole="button">
          <Text style={styles.stateActionText}>{actionLabel}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/** Aviso contextual (p. ej. "datos de ejemplo" o "dato declarado"). */
export function InfoBanner({ text, tone = 'info' }: { text: string; tone?: 'info' | 'warn' }) {
  const color = tone === 'warn' ? colors.warning : colors.cosmicBlue;
  const bg = tone === 'warn' ? 'rgba(255, 203, 107, 0.10)' : 'rgba(72, 123, 255, 0.10)';
  return (
    <View style={[styles.infoBanner, { borderColor: color, backgroundColor: bg }]}>
      <Text style={[styles.infoText, { color }]}>{text}</Text>
    </View>
  );
}

/* ----------------------------- Botón principal ---------------------------- */

export function GradientButton({
  label,
  onPress,
  disabled,
  loading,
  style,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  loading?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const inactive = disabled || loading;
  return (
    <Pressable
      onPress={onPress}
      disabled={inactive}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={({ pressed }) => [{ opacity: inactive ? 0.5 : pressed ? 0.85 : 1 }, style]}
    >
      <LinearGradient
        colors={gradients.primary}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={styles.btn}
      >
        {loading ? (
          <ActivityIndicator color={colors.softWhite} />
        ) : (
          <Text style={styles.btnText}>{label}</Text>
        )}
      </LinearGradient>
    </Pressable>
  );
}

/* ------------------------------ Botón ghost ------------------------------- */

export function GhostButton({
  label,
  onPress,
  disabled,
  style,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={({ pressed }) => [styles.ghost, { opacity: disabled ? 0.5 : pressed ? 0.7 : 1 }, style]}
    >
      <Text style={styles.ghostText}>{label}</Text>
    </Pressable>
  );
}

/* ------------------------------ Campo de texto ---------------------------- */

export function TextField({
  label,
  value,
  onChangeText,
  placeholder,
  secureTextEntry,
  keyboardType,
  autoCapitalize = 'none',
  editable = true,
  error,
  onSubmitEditing,
  returnKeyType,
}: {
  label: string;
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;
  secureTextEntry?: boolean;
  keyboardType?: KeyboardTypeOptions;
  autoCapitalize?: 'none' | 'sentences' | 'words' | 'characters';
  editable?: boolean;
  error?: string | null;
  onSubmitEditing?: () => void;
  returnKeyType?: 'done' | 'next' | 'send' | 'go';
}) {
  return (
    <View style={{ gap: 6 }}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        style={[styles.field, error ? styles.fieldError : null]}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={colors.textMuted}
        secureTextEntry={secureTextEntry}
        keyboardType={keyboardType}
        autoCapitalize={autoCapitalize}
        autoCorrect={false}
        editable={editable}
        onSubmitEditing={onSubmitEditing}
        returnKeyType={returnKeyType}
      />
      {error ? <Text style={styles.fieldErrorText}>{error}</Text> : null}
    </View>
  );
}

/* --------------------------------- Tarjeta -------------------------------- */

export function Card({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  return <View style={[styles.card, style]}>{children}</View>;
}

/* ------------------------------ Encabezados ------------------------------- */

export function SectionHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <View style={{ marginBottom: spacing.md }}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {subtitle ? <Text style={styles.sectionSubtitle}>{subtitle}</Text> : null}
    </View>
  );
}

/* ------------------------------- Badge demo ------------------------------- */

export function DemoBadge({ text = 'MODO DEMOSTRACIÓN' }: { text?: string }) {
  return (
    <View style={styles.demoBadge} accessibilityLabel={`${text}. Datos no reales.`}>
      <View style={styles.demoDot} />
      <Text style={styles.demoText}>{text}</Text>
    </View>
  );
}

export function Pill({ text, tone = 'neutral' }: { text: string; tone?: 'neutral' | 'ok' | 'warn' | 'info' }) {
  const toneColor =
    tone === 'ok' ? colors.success : tone === 'warn' ? colors.warning : tone === 'info' ? colors.cosmicBlue : colors.lavender;
  return (
    <View style={[styles.pill, { borderColor: toneColor }]}>
      <Text style={[styles.pillText, { color: toneColor }]}>{text}</Text>
    </View>
  );
}

/* -------------------------------- Stat tile ------------------------------- */

export function StatTile({ value, label, accent }: { value: string; label: string; accent?: string }) {
  return (
    <View style={styles.stat}>
      <Text style={[styles.statValue, accent ? { color: accent } : null]}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

/* ----------------------------- Barra de avance ---------------------------- */

export function ProgressBar({ pct }: { pct: number }) {
  const clamped = Math.max(0, Math.min(100, pct));
  return (
    <View style={styles.progressTrack}>
      <LinearGradient
        colors={gradients.primary}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 0 }}
        style={[styles.progressFill, { width: `${clamped}%` }]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  btn: {
    paddingVertical: 14,
    paddingHorizontal: spacing.xl,
    borderRadius: radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
    ...shadow.glow,
  },
  btnText: { color: colors.softWhite, fontWeight: '700', fontSize: 15 },
  ghost: {
    paddingVertical: 12,
    paddingHorizontal: spacing.lg,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ghostText: { color: colors.lavender, fontWeight: '600', fontSize: 14 },
  fieldLabel: { color: colors.textSecondary, fontSize: 13, fontWeight: '600' },
  field: {
    backgroundColor: colors.surfaceRaised,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: spacing.lg,
    paddingVertical: 12,
    color: colors.textPrimary,
    fontSize: 15,
  },
  fieldError: { borderColor: colors.danger },
  fieldErrorText: { color: colors.danger, fontSize: 12 },
  stateBox: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.xxl,
    paddingHorizontal: spacing.lg,
  },
  emptyTitle: { color: colors.textSecondary, fontSize: 16, fontWeight: '700', textAlign: 'center' },
  stateText: { color: colors.textMuted, fontSize: 13, textAlign: 'center', lineHeight: 19 },
  stateAction: {
    marginTop: spacing.sm,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    borderRadius: radius.pill,
    paddingHorizontal: spacing.lg,
    paddingVertical: 8,
  },
  stateActionText: { color: colors.lavender, fontSize: 13, fontWeight: '700' },
  infoBanner: {
    borderWidth: 1,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
  },
  infoText: { fontSize: 12, fontWeight: '600', lineHeight: 17 },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
    ...shadow.card,
  },
  sectionTitle: { ...typography.h2, color: colors.textPrimary },
  sectionSubtitle: { ...typography.small, color: colors.textMuted, marginTop: 2 },
  demoBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    backgroundColor: 'rgba(255, 203, 107, 0.12)',
    borderColor: colors.warning,
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: 5,
    borderRadius: radius.pill,
    gap: 6,
  },
  demoDot: { width: 7, height: 7, borderRadius: 7, backgroundColor: colors.warning },
  demoText: { color: colors.warning, fontSize: 11, fontWeight: '700', letterSpacing: 0.4 },
  pill: {
    borderWidth: 1,
    borderRadius: radius.pill,
    paddingHorizontal: spacing.md,
    paddingVertical: 3,
    alignSelf: 'flex-start',
  },
  pillText: { fontSize: 11, fontWeight: '600' },
  stat: {
    flex: 1,
    minWidth: 120,
    backgroundColor: colors.surfaceRaised,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.md,
  },
  statValue: { color: colors.textPrimary, fontSize: 22, fontWeight: '800' },
  statLabel: { color: colors.textMuted, fontSize: 12, marginTop: 2 },
  progressTrack: {
    height: 10,
    borderRadius: radius.pill,
    backgroundColor: colors.surfaceRaised,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.border,
  },
  progressFill: { height: '100%', borderRadius: radius.pill },
});
