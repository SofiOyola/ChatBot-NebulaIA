import React, { useEffect, useRef, useState } from 'react';
import { Image, Platform, StyleSheet, View, type ViewStyle } from 'react-native';

import type { NebulaState } from '../state/nebulaState';
import { NEBULA_SPRITES } from './sprites';

type Props = {
  /** Estado actual de la máquina del personaje. */
  state: NebulaState;
  /** Tamaño mostrado del lado del sprite en px (el lienzo original es 32x32). */
  size?: number;
  style?: ViewStyle;
};

/**
 * Reproduce la animación del gatito Nébula a partir de un spritesheet horizontal.
 *
 * - La animación está vinculada al estado real del chat (prop `state`), no a
 *   temporizadores sueltos: al cambiar de estado se reinicia en el frame 0.
 * - Técnica: contenedor recortado + Image desplazada en X por frame. Funciona
 *   igual en Android y web.
 * - Escalado pixel art nítido en web (image-rendering: pixelated). En nativo se
 *   usa el mejor ajuste disponible sin interpolación agresiva.
 */
export default function NebulaSprite({ state, size = 160, style }: Props) {
  const def = NEBULA_SPRITES[state];
  const scale = size / def.frameWidth;
  const [frame, setFrame] = useState(0);
  const frameRef = useRef(0);

  // Al cambiar de estado reiniciamos el ciclo de frames.
  useEffect(() => {
    frameRef.current = 0;
    setFrame(0);
  }, [state]);

  useEffect(() => {
    if (def.frameCount <= 1) return;
    const id = setInterval(() => {
      frameRef.current = (frameRef.current + 1) % def.frameCount;
      if (!def.loop && frameRef.current === 0) {
        frameRef.current = def.frameCount - 1;
        return;
      }
      setFrame(frameRef.current);
    }, def.frameDurationMs);
    return () => clearInterval(id);
  }, [def]);

  const containerSize = { width: def.frameWidth * scale, height: def.frameHeight * scale };

  return (
    <View style={[styles.wrap, containerSize, style]}>
      <Image
        source={def.source}
        resizeMode="stretch"
        style={[
          {
            width: def.frameWidth * def.frameCount * scale,
            height: def.frameHeight * scale,
            transform: [{ translateX: -frame * def.frameWidth * scale }],
          },
          pixelated,
        ]}
      />
    </View>
  );
}

// image-rendering: pixelated solo existe en web; en nativo se ignora sin error.
const pixelated: any =
  Platform.OS === 'web' ? { imageRendering: 'pixelated' } : undefined;

const styles = StyleSheet.create({
  wrap: {
    overflow: 'hidden',
  },
});
