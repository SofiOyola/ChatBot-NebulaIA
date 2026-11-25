import { LinearGradient } from 'expo-linear-gradient';
import React, { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { colors, gradients, radius, spacing } from '../theme/theme';
import type { ChatMessage } from '../types';

type Props = {
  message: ChatMessage;
  /** Si true, el texto aparece progresivamente durante `revealMs`. */
  reveal?: boolean;
  revealMs?: number;
};

/** Hook de aparición progresiva (typewriter) ligado a la duración dada. */
function useReveal(fullText: string, active: boolean, durationMs: number): string {
  const [shown, setShown] = useState(active ? '' : fullText);
  const raf = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!active) {
      setShown(fullText);
      return;
    }
    const total = fullText.length;
    if (total === 0) return;
    const stepMs = Math.max(16, durationMs / total);
    let i = 0;
    setShown('');
    raf.current = setInterval(() => {
      i += 1;
      setShown(fullText.slice(0, i));
      if (i >= total && raf.current) {
        clearInterval(raf.current);
        raf.current = null;
      }
    }, stepMs);
    return () => {
      if (raf.current) clearInterval(raf.current);
    };
  }, [fullText, active, durationMs]);

  return shown;
}

export default function ChatBubble({ message, reveal = false, revealMs = 0 }: Props) {
  const isUser = message.role === 'user';
  const text = useReveal(message.text, reveal && !isUser, revealMs);

  if (isUser) {
    return (
      <View style={[styles.row, styles.rowUser]}>
        <LinearGradient
          colors={gradients.primary}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={[styles.bubble, styles.userBubble]}
        >
          <Text style={styles.userText}>{message.text}</Text>
        </LinearGradient>
      </View>
    );
  }

  return (
    <View style={[styles.row, styles.rowAssistant]}>
      <View style={[styles.bubble, styles.assistantBubble]}>
        <Text style={styles.assistantText}>{text}</Text>
        {message.demo ? <Text style={styles.demoTag}>respuesta de demostración</Text> : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { width: '100%', marginVertical: spacing.xs, flexDirection: 'row' },
  rowUser: { justifyContent: 'flex-end' },
  rowAssistant: { justifyContent: 'flex-start' },
  bubble: {
    maxWidth: '86%',
    paddingVertical: 10,
    paddingHorizontal: 14,
    borderRadius: radius.lg,
  },
  userBubble: { borderBottomRightRadius: 6 },
  assistantBubble: {
    backgroundColor: colors.surfaceRaised,
    borderColor: colors.border,
    borderWidth: 1,
    borderBottomLeftRadius: 6,
  },
  userText: { color: colors.softWhite, fontSize: 15, lineHeight: 21 },
  assistantText: { color: colors.textPrimary, fontSize: 15, lineHeight: 21 },
  demoTag: {
    color: colors.textMuted,
    fontSize: 10,
    fontStyle: 'italic',
    marginTop: 6,
  },
});
