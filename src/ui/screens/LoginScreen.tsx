import React, { useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import NebulaStage from '../components/NebulaStage';
import { Card, GradientButton, TextField } from '../components/ui';
import { useSession } from '../session/SessionContext';
import { colors, spacing } from '../theme/theme';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default function LoginScreen() {
  const session = useSession();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [emailError, setEmailError] = useState<string | null>(null);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const validate = (): boolean => {
    let ok = true;
    if (!EMAIL_RE.test(email.trim())) {
      setEmailError('Introduce un correo válido.');
      ok = false;
    } else setEmailError(null);
    if (password.length === 0) {
      setPasswordError('Introduce tu contraseña.');
      ok = false;
    } else setPasswordError(null);
    return ok;
  };

  const onSubmit = async () => {
    setFormError(null);
    if (loading) return;
    if (!validate()) return;
    setLoading(true);
    const result = await session.signIn(email.trim(), password);
    setLoading(false);
    if (!result.ok) {
      setFormError(result.message);
      return;
    }
    // Éxito: el SessionProvider detecta la sesión y la navegación cambia sola.
  };

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.brand}>
          <View style={styles.stageWrap}>
            <NebulaStage state="idle" size={120} compact />
          </View>
          <Text style={styles.title}>NébulaIA</Text>
          <Text style={styles.subtitle}>Asistente académico de la UNAB</Text>
        </View>

        <Card style={styles.card}>
          <Text style={styles.cardTitle}>Iniciar sesión</Text>
          <TextField
            label="Correo institucional"
            value={email}
            onChangeText={setEmail}
            placeholder="tu.correo@unab.edu.co"
            keyboardType="email-address"
            error={emailError}
            returnKeyType="next"
          />
          <View style={{ height: spacing.md }} />
          <TextField
            label="Contraseña"
            value={password}
            onChangeText={setPassword}
            placeholder="••••••••"
            secureTextEntry
            error={passwordError}
            returnKeyType="go"
            onSubmitEditing={onSubmit}
          />

          {formError ? (
            <View style={styles.errorBox}>
              <Text style={styles.errorText}>⚠️ {formError}</Text>
            </View>
          ) : null}

          <View style={{ height: spacing.lg }} />
          <GradientButton
            label={loading ? 'Entrando…' : 'Entrar'}
            onPress={onSubmit}
            loading={loading}
            disabled={loading}
          />
          <Text style={styles.note}>
            Autenticación segura con Supabase. Tu contraseña nunca se almacena en la app.
          </Text>
        </Card>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  content: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: spacing.xl,
    gap: spacing.xl,
    maxWidth: 480,
    width: '100%',
    alignSelf: 'center',
  },
  brand: { alignItems: 'center', gap: spacing.sm },
  stageWrap: { width: 180, height: 180 },
  title: { color: colors.softWhite, fontSize: 30, fontWeight: '900', letterSpacing: 0.5 },
  subtitle: { color: colors.textSecondary, fontSize: 14 },
  card: { gap: spacing.xs },
  cardTitle: { color: colors.textPrimary, fontSize: 18, fontWeight: '700', marginBottom: spacing.md },
  errorBox: {
    marginTop: spacing.md,
    backgroundColor: 'rgba(255, 107, 138, 0.12)',
    borderColor: colors.danger,
    borderWidth: 1,
    borderRadius: 12,
    padding: spacing.md,
  },
  errorText: { color: colors.danger, fontSize: 13 },
  note: { color: colors.textMuted, fontSize: 11, marginTop: spacing.md, textAlign: 'center' },
});
