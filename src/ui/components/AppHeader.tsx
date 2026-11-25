import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useSession, type BackendStatus } from '../session/SessionContext';
import { colors, radius, spacing } from '../theme/theme';

/** Etiqueta y color por estado real del backend conversacional. */
function connection(status: BackendStatus): { label: string; color: string } {
  switch (status) {
    case 'unconfigured':
      return { label: 'Sin configurar', color: colors.textMuted };
    case 'connecting':
      return { label: 'Conectando…', color: colors.cosmicBlue };
    case 'connected':
      return { label: 'Conectado', color: colors.success };
    case 'error':
      return { label: 'Sin conexión', color: colors.danger };
    case 'ready':
    default:
      return { label: 'Sin verificar', color: colors.lavender };
  }
}

/** Barra superior visible solo con sesión iniciada: conexión, usuario y salir. */
export default function AppHeader() {
  const session = useSession();
  if (session.status !== 'signedIn') return null;

  const conn = connection(session.backendStatus);
  const email = session.user?.email ?? 'Sesión activa';

  return (
    <View style={styles.bar}>
      <View style={styles.left}>
        <View style={[styles.dot, { backgroundColor: conn.color }]} />
        <Text style={[styles.conn, { color: conn.color }]} numberOfLines={1}>
          {conn.label}
        </Text>
      </View>
      <Text style={styles.email} numberOfLines={1}>
        {email}
      </Text>
      <Pressable
        onPress={session.signOut}
        accessibilityRole="button"
        accessibilityLabel="Cerrar sesión"
        style={({ pressed }) => [styles.logout, { opacity: pressed ? 0.6 : 1 }]}
      >
        <Text style={styles.logoutText}>Salir</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    backgroundColor: 'rgba(9, 9, 20, 0.5)',
  },
  left: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  dot: { width: 8, height: 8, borderRadius: 8 },
  conn: { fontSize: 12, fontWeight: '700' },
  email: { flex: 1, textAlign: 'center', color: colors.textMuted, fontSize: 12 },
  logout: {
    borderWidth: 1,
    borderColor: colors.borderStrong,
    borderRadius: radius.pill,
    paddingHorizontal: spacing.md,
    paddingVertical: 5,
  },
  logoutText: { color: colors.lavender, fontSize: 12, fontWeight: '700' },
});
