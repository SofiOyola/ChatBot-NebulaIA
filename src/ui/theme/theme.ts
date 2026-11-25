/**
 * Identidad visual de NébulaIA 2.0.
 * Paleta galáctica compartida por toda la interfaz.
 */

export const colors = {
  // Fondos
  spaceBlack: '#090914',
  deepPurple: '#171033',
  // Acentos
  purple: '#7955E8',
  cosmicBlue: '#487BFF',
  lavender: '#C8B9FF',
  softWhite: '#F5F3FF',
  // Derivados de apoyo (misma familia, sin introducir colores nuevos)
  surface: '#141028',
  surfaceRaised: '#1E1740',
  border: 'rgba(200, 185, 255, 0.14)',
  borderStrong: 'rgba(121, 85, 232, 0.45)',
  textPrimary: '#F5F3FF',
  textSecondary: '#C8B9FF',
  textMuted: 'rgba(200, 185, 255, 0.62)',
  danger: '#FF6B8A',
  success: '#5EE6B5',
  warning: '#FFCB6B',
} as const;

export const gradients = {
  // Fondo general de la aplicación
  space: ['#090914', '#171033', '#0C0A20'] as const,
  // Entorno del gatito Nébula
  nebula: ['#1E1740', '#2A1B5E', '#171033'] as const,
  // Botón principal
  primary: ['#7955E8', '#487BFF'] as const,
  // Burbuja del asistente
  assistant: ['#1E1740', '#241a4d'] as const,
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
} as const;

export const radius = {
  sm: 10,
  md: 16,
  lg: 22,
  xl: 28,
  pill: 999,
} as const;

export const typography = {
  h1: { fontSize: 24, fontWeight: '700' as const },
  h2: { fontSize: 19, fontWeight: '700' as const },
  h3: { fontSize: 16, fontWeight: '600' as const },
  body: { fontSize: 15, fontWeight: '400' as const },
  small: { fontSize: 13, fontWeight: '400' as const },
  tiny: { fontSize: 11, fontWeight: '500' as const },
};

export const shadow = {
  glow: {
    shadowColor: colors.purple,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.55,
    shadowRadius: 18,
    elevation: 8,
  },
  card: {
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.35,
    shadowRadius: 16,
    elevation: 6,
  },
};
