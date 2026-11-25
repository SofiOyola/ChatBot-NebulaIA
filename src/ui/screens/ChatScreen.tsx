import React, { useEffect, useRef, useState } from 'react';
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from 'react-native';
import ChatBubble from '../components/ChatBubble';
import NebulaStage from '../components/NebulaStage';
import TypingIndicator from '../components/TypingIndicator';
import { DemoBadge } from '../components/ui';
import { useKeyboard } from '../hooks/useKeyboard';
import { useNebulaChat } from '../hooks/useNebulaChat';
import { colors, radius, spacing } from '../theme/theme';

export default function ChatScreen() {
  const chat = useNebulaChat();
  const [input, setInput] = useState('');
  const { width, height } = useWindowDimensions();
  const keyboard = useKeyboard();
  const scrollRef = useRef<React.ComponentRef<typeof ScrollView>>(null);
  const composerRef = useRef<React.ComponentRef<typeof View>>(null);
  const isWide = width >= 820;
  const isShortMobile = !isWide && height < 780;
  const keyboardVisible = keyboard.visible;
  // En móvil, al abrir el teclado el gatito cede su espacio al chat (no se deforma,
  // simplemente deja de ocupar área) para que el compositor quede sobre el teclado.
  const showStage = isWide || !keyboardVisible;
  // En Android edge-to-edge la ventana NO se redimensiona con el teclado, así que
  // desplazamos el compositor con la altura real del teclado. En web no aplica.
  const liftForKeyboard = Platform.OS !== 'web' && keyboardVisible ? keyboard.height : 0;

  useEffect(() => {
    // Mantener la conversación desplazada al final.
    const t = setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 60);
    return () => clearTimeout(t);
  }, [chat.messages.length, chat.nebulaState, keyboardVisible]);

  // Comprobación de layout (solo desarrollo): verifica que el borde inferior del
  // compositor quede por encima del borde superior del teclado. No registra datos
  // privados: solo métricas de layout y un booleano.
  useEffect(() => {
    // eslint-disable-next-line no-undef
    if (typeof __DEV__ === 'undefined' || !__DEV__) return;
    if (!keyboardVisible || Platform.OS === 'web') return;
    const t = setTimeout(() => {
      composerRef.current?.measureInWindow((_x, y, _w, h) => {
        const composerBottom = y + h;
        const ok = composerBottom <= Math.ceil(keyboard.top) + 1;
        console.log('[layout] composer sobre teclado:', ok, {
          composerBottom: Math.round(composerBottom),
          keyboardTop: Math.round(keyboard.top),
        });
      });
    }, 120);
    return () => clearTimeout(t);
  }, [keyboardVisible, keyboard.top, keyboard.height]);

  const onSend = () => {
    if (!chat.canSend) return;
    const text = input;
    setInput('');
    chat.send(text);
  };

  const stage = (
    <View style={isWide ? styles.stageWide : [styles.stageMobile, isShortMobile && styles.stageCompact]}>
      <NebulaStage
        state={chat.nebulaState}
        size={isWide ? 180 : isShortMobile ? 112 : 132}
        compact={isShortMobile}
      />
    </View>
  );

  const conversation = (
    <View style={isWide ? styles.chatWide : styles.chatMobile}>
      <View style={styles.chatHeader}>
        <Text style={styles.chatTitle}>Conversación</Text>
        {chat.isDemo ? <DemoBadge /> : null}
      </View>

      <ScrollView
        ref={scrollRef}
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
      >
        {chat.messages.map((m) => (
          <ChatBubble
            key={m.id}
            message={m}
            reveal={m.id === chat.revealId}
            revealMs={chat.revealMs}
          />
        ))}
        {chat.nebulaState === 'thinking' ? <TypingIndicator /> : null}
      </ScrollView>

      {chat.error ? (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>⚠️ {chat.error}</Text>
          <View style={styles.errorActions}>
            {chat.errorRetryable ? (
              <Pressable onPress={chat.retry} accessibilityRole="button" accessibilityLabel="Reintentar">
                <Text style={styles.errorAction}>Reintentar</Text>
              </Pressable>
            ) : null}
            <Pressable onPress={chat.dismissError} accessibilityRole="button" accessibilityLabel="Cerrar error">
              <Text style={styles.errorActionMuted}>Cerrar</Text>
            </Pressable>
          </View>
        </View>
      ) : null}

      <View ref={composerRef} style={styles.inputRow}>
        <TextInput
          style={styles.input}
          value={input}
          onChangeText={setInput}
          placeholder="Escribe tu pregunta…"
          placeholderTextColor={colors.textMuted}
          multiline
          textAlignVertical="top"
          editable
        />
        <Pressable
          onPress={onSend}
          disabled={!chat.canSend || input.trim().length === 0}
          accessibilityRole="button"
          accessibilityLabel="Enviar pregunta"
          style={({ pressed }) => [
            styles.sendBtn,
            {
              opacity: !chat.canSend || input.trim().length === 0 ? 0.45 : pressed ? 0.8 : 1,
            },
          ]}
        >
          <Text style={styles.sendIcon}>➤</Text>
        </Pressable>
      </View>
    </View>
  );

  return (
    <View
      style={[
        styles.container,
        isWide ? styles.rowLayout : styles.columnLayout,
        isShortMobile && styles.containerCompact,
        // Desplaza TODO el contenido para que el compositor quede sobre el teclado.
        { paddingBottom: spacing.md + liftForKeyboard },
      ]}
    >
      {showStage ? stage : null}
      {conversation}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, minHeight: 0, padding: spacing.md, gap: spacing.md, overflow: 'hidden' },
  containerCompact: { padding: spacing.sm, gap: spacing.sm },
  columnLayout: { flexDirection: 'column' },
  rowLayout: { flexDirection: 'row' },

  // Mobile: ~40% personaje / 60% chat.
  stageMobile: { flexGrow: 0, flexShrink: 0, flexBasis: 'auto', height: 210, minHeight: 0 },
  stageCompact: { height: 150 },
  chatMobile: { flex: 1, minHeight: 0 },
  // Web/ancho: distribución horizontal 40/60.
  stageWide: { flex: 4, maxWidth: 520 },
  chatWide: { flex: 6, minWidth: 0, minHeight: 0 },

  chatHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.sm,
    gap: spacing.sm,
    flexWrap: 'wrap',
  },
  chatTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '700' },
  scroll: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
  },
  scrollContent: { padding: spacing.md, paddingBottom: spacing.lg },
  errorBanner: {
    marginTop: spacing.sm,
    backgroundColor: 'rgba(255, 107, 138, 0.12)',
    borderColor: colors.danger,
    borderWidth: 1,
    borderRadius: radius.md,
    padding: spacing.md,
  },
  errorText: { color: colors.danger, fontSize: 13 },
  errorActions: { flexDirection: 'row', gap: spacing.lg, marginTop: spacing.sm, justifyContent: 'flex-end' },
  errorAction: { color: colors.lavender, fontSize: 13, fontWeight: '700' },
  errorActionMuted: { color: colors.textMuted, fontSize: 13, fontWeight: '600' },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: spacing.sm,
    marginTop: spacing.sm,
  },
  input: {
    flex: 1,
    minHeight: 48,
    maxHeight: 120,
    backgroundColor: colors.surfaceRaised,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: spacing.lg,
    paddingTop: Platform.OS === 'web' ? 14 : 12,
    paddingBottom: 12,
    color: colors.textPrimary,
    fontSize: 15,
  },
  sendBtn: {
    width: 48,
    height: 48,
    borderRadius: 48,
    backgroundColor: colors.purple,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendIcon: { color: colors.softWhite, fontSize: 18, fontWeight: '700' },
});
