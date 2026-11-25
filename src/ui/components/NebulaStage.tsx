import { LinearGradient } from 'expo-linear-gradient';
import React from 'react';
import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import type { NebulaState } from '../state/nebulaState';
import { colors, gradients, radius, spacing } from '../theme/theme';
import NebulaSprite from './NebulaSprite';

const CAPTION: Record<NebulaState, string> = {
  idle: 'Listo para ayudarte',
  thinking: 'Procesando tu pregunta…',
  talking: 'Nébula te responde',
};

type Props = {
  state: NebulaState;
  size?: number;
  compact?: boolean;
  style?: ViewStyle;
};

/** Entorno visual del gatito Nébula: halo, pedestal luminoso y leyenda de estado. */
export default function NebulaStage({ state, size = 150, compact = false, style }: Props) {
  return (
    <LinearGradient colors={gradients.nebula} style={[styles.stage, style]}>
      <View style={styles.glow} pointerEvents="none" />
      <View style={styles.spriteWrap}>
        <NebulaSprite state={state} size={size} />
        <View style={styles.pedestal} pointerEvents="none" />
      </View>
      {!compact && (
        <View style={styles.caption}>
          <View
            style={[
              styles.statusDot,
              {
                backgroundColor:
                  state === 'thinking' ? colors.warning : state === 'talking' ? colors.success : colors.lavender,
              },
            ]}
          />
          <Text style={styles.captionText}>{CAPTION[state]}</Text>
        </View>
      )}
      {!compact && <Text style={styles.name}>Nébula</Text>}
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  stage: {
    flex: 1,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
    paddingVertical: spacing.lg,
  },
  glow: {
    position: 'absolute',
    width: 240,
    height: 240,
    borderRadius: 240,
    backgroundColor: colors.purple,
    opacity: 0.22,
    top: '18%',
  },
  spriteWrap: { alignItems: 'center', justifyContent: 'center' },
  pedestal: {
    marginTop: 6,
    width: 120,
    height: 16,
    borderRadius: 120,
    backgroundColor: colors.cosmicBlue,
    opacity: 0.25,
    transform: [{ scaleY: 0.5 }],
  },
  caption: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    marginTop: spacing.md,
    backgroundColor: 'rgba(9, 9, 20, 0.4)',
    paddingHorizontal: spacing.md,
    paddingVertical: 5,
    borderRadius: radius.pill,
  },
  statusDot: { width: 8, height: 8, borderRadius: 8 },
  captionText: { color: colors.textSecondary, fontSize: 13, fontWeight: '500' },
  name: { color: colors.softWhite, fontSize: 18, fontWeight: '800', marginTop: 6, letterSpacing: 0.5 },
});
