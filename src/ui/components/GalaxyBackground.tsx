import { LinearGradient } from 'expo-linear-gradient';
import React, { useMemo } from 'react';
import { StyleSheet, View, type ViewStyle } from 'react-native';

import { colors, gradients } from '../theme/theme';

type Props = {
  children?: React.ReactNode;
  style?: ViewStyle;
  /** Número de estrellas discretas. */
  stars?: number;
};

type Star = { top: string; left: string; size: number; opacity: number };

function buildStars(count: number): Star[] {
  const out: Star[] = [];
  // Distribución pseudoaleatoria determinista (sin dependencias, estable entre renders).
  let seed = 7;
  const rand = () => {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
  for (let i = 0; i < count; i += 1) {
    out.push({
      top: `${Math.round(rand() * 100)}%`,
      left: `${Math.round(rand() * 100)}%`,
      size: rand() > 0.85 ? 2.5 : 1.5,
      opacity: 0.25 + rand() * 0.5,
    });
  }
  return out;
}

/** Fondo reutilizable: gradiente espacial + estrellas discretas + halo sutil. */
export default function GalaxyBackground({ children, style, stars = 46 }: Props) {
  const starField = useMemo(() => buildStars(stars), [stars]);
  return (
    <LinearGradient colors={gradients.space} style={[styles.fill, style]}>
      <View pointerEvents="none" style={StyleSheet.absoluteFill}>
        {starField.map((s, i) => (
          <View
            key={i}
            style={{
              position: 'absolute',
              top: s.top as any,
              left: s.left as any,
              width: s.size,
              height: s.size,
              borderRadius: s.size,
              backgroundColor: colors.lavender,
              opacity: s.opacity,
            }}
          />
        ))}
        {/* Halo luminoso difuso en la parte superior */}
        <View style={styles.halo} />
      </View>
      {children}
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, minHeight: 0, overflow: 'hidden' },
  halo: {
    position: 'absolute',
    top: -120,
    alignSelf: 'center',
    width: 320,
    height: 320,
    borderRadius: 320,
    backgroundColor: colors.purple,
    opacity: 0.16,
  },
});
