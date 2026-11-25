import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { DarkTheme, NavigationContainer, useIsFocused, type Theme } from '@react-navigation/native';
import React from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import ChatScreen from '../screens/ChatScreen';
import EstadoAcademicoScreen from '../screens/EstadoAcademicoScreen';
import MatriculaScreen from '../screens/MatriculaScreen';
import ProyeccionScreen from '../screens/ProyeccionScreen';
import RecomendacionesScreen from '../screens/RecomendacionesScreen';
import { colors } from '../theme/theme';

const Tab = createBottomTabNavigator();

const navTheme: Theme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: 'transparent',
    card: 'rgba(9, 9, 20, 0.86)',
    primary: colors.purple,
    text: colors.textPrimary,
    border: colors.border,
    notification: colors.cosmicBlue,
  },
};

const ICONS: Record<string, string> = {
  Chat: '💬',
  Matrícula: '📝',
  Estado: '📊',
  Proyección: '🚀',
  Recomendaciones: '✨',
};

function tabIcon(route: string, color: string, focused: boolean) {
  return (
    <Text style={{ fontSize: focused ? 23 : 21, color, opacity: focused ? 1 : 0.9 }}>
      {ICONS[route] ?? '•'}
    </Text>
  );
}

/**
 * React Navigation conserva las escenas para preservar su estado. En web, la
 * combinación actual de react-navigation/react-native-screens no oculta de
 * forma fiable la escena inactiva. Esta envoltura mantiene cada ruta montada
 * (chat, formularios y sesión conservan su estado), pero hace explícito que
 * solo la ruta enfocada participa en el layout y en la accesibilidad.
 */
function IsolatedTabScene({ children }: { children: React.ReactNode }) {
  const isFocused = useIsFocused();
  return (
    <View
      accessibilityElementsHidden={!isFocused}
      importantForAccessibility={isFocused ? 'auto' : 'no-hide-descendants'}
      pointerEvents={isFocused ? 'auto' : 'none'}
      style={[styles.scene, !isFocused && styles.hiddenScene]}
    >
      {children}
    </View>
  );
}

const ChatRoute = () => <IsolatedTabScene><ChatScreen /></IsolatedTabScene>;
const MatriculaRoute = () => <IsolatedTabScene><MatriculaScreen /></IsolatedTabScene>;
const EstadoRoute = () => <IsolatedTabScene><EstadoAcademicoScreen /></IsolatedTabScene>;
const ProyeccionRoute = () => <IsolatedTabScene><ProyeccionScreen /></IsolatedTabScene>;
const RecomendacionesRoute = () => <IsolatedTabScene><RecomendacionesScreen /></IsolatedTabScene>;

export default function RootNavigator() {
  const insets = useSafeAreaInsets();
  const isWeb = Platform.OS === 'web';
  // Reservar el área del sistema Android (gestos o botones) bajo la barra, con un
  // mínimo para separar las zonas táctiles del borde inferior.
  const bottomInset = isWeb ? 0 : Math.max(insets.bottom, 10);
  // Altura del contenido de cada pestaña (≈48 dp de zona táctil) + inset real.
  const barHeight = (isWeb ? 64 : 58) + bottomInset;

  return (
    <NavigationContainer theme={navTheme}>
      <Tab.Navigator
        detachInactiveScreens={false}
        screenOptions={({ route }) => ({
          headerShown: false,
          tabBarActiveTintColor: colors.lavender,
          tabBarInactiveTintColor: colors.textMuted,
          // Oculta la barra mientras el teclado está abierto (más espacio para el chat).
          tabBarHideOnKeyboard: true,
          tabBarIcon: ({ color, focused }) => tabIcon(route.name, color, focused),
          tabBarStyle: {
            backgroundColor: 'rgba(9, 9, 20, 0.96)',
            borderTopColor: colors.border,
            borderTopWidth: StyleSheet.hairlineWidth,
            height: barHeight,
            paddingBottom: bottomInset,
            paddingTop: 8,
          },
          tabBarItemStyle: { minHeight: 48, paddingVertical: 4 },
          tabBarLabelStyle: { fontSize: 11, fontWeight: '600', marginTop: 2 },
          tabBarIconStyle: { marginTop: 1 },
          sceneStyle: styles.navigatorScene,
        })}
      >
        <Tab.Screen name="Chat" component={ChatRoute} />
        <Tab.Screen name="Matrícula" component={MatriculaRoute} />
        <Tab.Screen name="Estado" component={EstadoRoute} />
        <Tab.Screen name="Proyección" component={ProyeccionRoute} />
        <Tab.Screen
          name="Recomendaciones"
          component={RecomendacionesRoute}
          options={{ tabBarLabel: 'Recom.' }}
        />
      </Tab.Navigator>
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  navigatorScene: { flex: 1, minHeight: 0, overflow: 'hidden' },
  scene: { flex: 1, minHeight: 0 },
  hiddenScene: { display: 'none' },
});
