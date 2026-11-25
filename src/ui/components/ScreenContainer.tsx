import React from 'react';
import { ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';

import { colors, spacing } from '../theme/theme';

type Props = {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  headerRight?: React.ReactNode;
};

/** Marco común de las pantallas académicas: título, subtítulo y scroll centrado. */
export default function ScreenContainer({ title, subtitle, children, headerRight }: Props) {
  const { width } = useWindowDimensions();
  const maxWidth = width >= 900 ? 820 : undefined;
  const compactHeader = width < 520;
  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={[
        styles.content,
        maxWidth ? { maxWidth, alignSelf: 'center', width: '100%' } : null,
      ]}
      keyboardShouldPersistTaps="handled"
      showsHorizontalScrollIndicator={false}
    >
      <View style={[styles.header, compactHeader && styles.headerCompact]}>
        <View style={styles.headerCopy}>
          <Text style={styles.title}>{title}</Text>
          {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
        </View>
        {headerRight}
      </View>
      {children}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: { flex: 1, minHeight: 0 },
  content: { flexGrow: 1, padding: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.md },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    marginBottom: spacing.xs,
  },
  headerCompact: { flexDirection: 'column', alignItems: 'stretch' },
  headerCopy: { flex: 1, minWidth: 0 },
  title: { color: colors.textPrimary, fontSize: 24, fontWeight: '800' },
  subtitle: { color: colors.textMuted, fontSize: 13, marginTop: 4, lineHeight: 18 },
});
