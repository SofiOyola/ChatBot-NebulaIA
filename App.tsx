import { StatusBar } from 'expo-status-bar';
import React from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

import AppHeader from './src/ui/components/AppHeader';
import GalaxyBackground from './src/ui/components/GalaxyBackground';
import RootNavigator from './src/ui/navigation/RootNavigator';
import LoginScreen from './src/ui/screens/LoginScreen';
import { SessionProvider, useSession } from './src/ui/session/SessionContext';
import { colors } from './src/ui/theme/theme';

/** Compuerta de autenticación: cargando -> login -> aplicación. */
function Gate() {
  const session = useSession();

  // Si la autenticación no está configurada, la app funciona en modo demo.
  if (!session.authConfigured) {
    return <RootNavigator />;
  }

  if (session.status === 'loading') {
    return (
      <View style={styles.center}>
        <ActivityIndicator color={colors.lavender} size="large" />
        <Text style={styles.loadingText}>Restaurando sesión…</Text>
      </View>
    );
  }

  if (session.status === 'signedOut') {
    return <LoginScreen />;
  }

  return (
    <View style={styles.app}>
      <AppHeader />
      <RootNavigator />
    </View>
  );
}

/**
 * NébulaIA 2.0 — Asistente académico de la UNAB.
 * Fondo galáctico compartido detrás de la autenticación y la navegación.
 */
export default function App() {
  return (
    <SafeAreaProvider>
      <SessionProvider>
        <View style={styles.root}>
          <GalaxyBackground>
            <SafeAreaView style={styles.safe} edges={['top']}>
              <Gate />
            </SafeAreaView>
          </GalaxyBackground>
        </View>
        <StatusBar style="light" />
      </SessionProvider>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, minHeight: 0, backgroundColor: colors.spaceBlack, overflow: 'hidden' },
  safe: { flex: 1, minHeight: 0 },
  app: { flex: 1, minHeight: 0 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 },
  loadingText: { color: colors.textSecondary, fontSize: 14 },
});
