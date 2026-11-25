/**
 * Catálogo de spritesheets del gatito Nébula.
 *
 * Fuente única: los tres archivos originales .ase diseñados a mano,
 * exportados con LibreSprite a spritesheets PNG horizontales sin alterar
 * dibujos, colores ni fotogramas. Metadatos verificados desde el JSON de
 * exportación (assets/nebula/*.json):
 *
 *   GatoIdle     -> 32x32, 2 frames, 500 ms/frame
 *   GatoTalking  -> 32x32, 2 frames, 500 ms/frame
 *   GatoThinking -> 32x32, 6 frames, 300 ms/frame
 *
 * Todas las animaciones comparten el lienzo de 32x32, por lo que el personaje
 * no cambia de posición ni de tamaño al cambiar de estado.
 */

import type { ImageSourcePropType } from 'react-native';

import type { NebulaState } from '../state/nebulaState';

export type SpriteDef = {
  source: ImageSourcePropType;
  frameWidth: number;
  frameHeight: number;
  frameCount: number;
  /** Duración de cada frame en milisegundos (uniforme en estas animaciones). */
  frameDurationMs: number;
  loop: boolean;
};

export const NEBULA_SPRITES: Record<NebulaState, SpriteDef> = {
  idle: {
    source: require('../../../assets/nebula/GatoIdle.png'),
    frameWidth: 32,
    frameHeight: 32,
    frameCount: 2,
    frameDurationMs: 500,
    loop: true,
  },
  thinking: {
    source: require('../../../assets/nebula/GatoThinking.png'),
    frameWidth: 32,
    frameHeight: 32,
    frameCount: 6,
    frameDurationMs: 300,
    loop: true,
  },
  talking: {
    source: require('../../../assets/nebula/GatoTalking.png'),
    frameWidth: 32,
    frameHeight: 32,
    frameCount: 2,
    frameDurationMs: 500,
    loop: true,
  },
};
