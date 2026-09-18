/// 主题与视觉规范：深空青金 + Material 3。
library;

import 'package:flutter/material.dart';

/// 主色板（沿用旧版配色，明度微调以适配 Material 3）。
abstract final class AppColors {
  static const Color backdrop = Color(0xFF070D1C);
  static const Color surface = Color(0xFF111A2E);
  static const Color surfaceHigh = Color(0xFF1B2030);
  static const Color outline = Color(0x33F7E2A8);
  static const Color gold = Color(0xFFF7E2A8);
  static const Color goldDeep = Color(0xFFD4B886);
  static const Color goldDark = Color(0xFF8C6F46);
  static const Color text = Color(0xFFF3EAD6);
  static const Color textMuted = Color(0xFFB8AD96);
  static const Color textFaint = Color(0xFF8F8FA8);
  static const Color jade = Color(0xFF7DFF9E);
  static const Color danger = Color(0xFFFF8A8A);
  static const Color info = Color(0xFF7DB8FF);
  static const Color violet = Color(0xFFD4A0FF);
}

/// 职务徽章配色。
Color roleColor(String role) => switch (role) {
  '宗主' => const Color(0xFFFFD766),
  '长老' => const Color(0xFFD4A0FF),
  '峰主' => const Color(0xFFFFC98A),
  '执事' => const Color(0xFF7DB8FF),
  '第一天骄' => const Color(0xFFFFE082),
  '第二天骄' => const Color(0xFFF7D36A),
  '天骄' => const Color(0xFFF7E2A8),
  '核心弟子' => const Color(0xFF9AE6C8),
  '内门弟子' => const Color(0xFF8FD3F4),
  '外门弟子' => const Color(0xFFC9BFAE),
  '凡人' => const Color(0xFF9AA0A6),
  '通天塔榜首' => const Color(0xFFFFD766),
  _ => AppColors.textMuted,
};

/// 境界配色。
Color rankColor(String mainRank) => switch (mainRank) {
  '炼气' => const Color(0xFF9ADCA0),
  '筑基' => const Color(0xFF7DDFF4),
  '金丹' => const Color(0xFFFFD766),
  '元婴' => const Color(0xFFD4A0FF),
  '化神' => const Color(0xFFFF9F8A),
  '炼虚' => const Color(0xFFF7E2A8),
  _ => AppColors.textMuted,
};

/// 名次配色：金 / 浅金 / 暖铜。
Color rankMedalColor(int index) => switch (index) {
  0 => const Color(0xFFFFD766),
  1 => const Color(0xFFF7E2A8),
  2 => const Color(0xFFD9A06A),
  _ => AppColors.textMuted,
};

ThemeData buildAppTheme() {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.goldDeep,
        brightness: Brightness.dark,
      ).copyWith(
        surface: AppColors.surface,
        onSurface: AppColors.text,
        primary: AppColors.gold,
        onPrimary: const Color(0xFF20180A),
        secondary: AppColors.jade,
        onSecondary: const Color(0xFF07200F),
        error: AppColors.danger,
        outline: AppColors.outline,
      );

  final TextTheme base = Typography.material2021(
    platform: TargetPlatform.android,
  ).white;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.backdrop,
    textTheme: base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        color: AppColors.gold,
        letterSpacing: 4,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: AppColors.gold,
        letterSpacing: 3,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: AppColors.gold,
        letterSpacing: 1.5,
      ),
      titleMedium: base.titleMedium?.copyWith(color: AppColors.text),
      bodyMedium: base.bodyMedium?.copyWith(color: AppColors.text),
      bodySmall: base.bodySmall?.copyWith(color: AppColors.textMuted),
      labelLarge: base.labelLarge?.copyWith(letterSpacing: 1),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceHigh.withValues(alpha: 0.82),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x33101A2E),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x44F7E2A8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x33F7E2A8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.gold),
      ),
      hintStyle: const TextStyle(color: AppColors.textFaint),
      labelStyle: const TextStyle(color: AppColors.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.goldDeep,
        foregroundColor: const Color(0xFF20180A),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.gold,
        side: const BorderSide(color: Color(0x66D4B886)),
        textStyle: const TextStyle(letterSpacing: 1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.goldDeep),
    ),
    dividerTheme: const DividerThemeData(color: Color(0x22F7E2A8), space: 24),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color(0xCC0C1426),
      indicatorColor: Color(0x33F7E2A8),
      selectedIconTheme: IconThemeData(color: AppColors.gold),
      unselectedIconTheme: IconThemeData(color: AppColors.textFaint),
      selectedLabelTextStyle: TextStyle(
        color: AppColors.gold,
        letterSpacing: 1,
      ),
      unselectedLabelTextStyle: TextStyle(color: AppColors.textMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xF00C1426),
      indicatorColor: const Color(0x33F7E2A8),
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      iconTheme: const WidgetStatePropertyAll<IconThemeData>(
        IconThemeData(color: AppColors.goldDeep),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.gold,
      titleTextStyle: TextStyle(
        color: AppColors.gold,
        fontSize: 20,
        letterSpacing: 3,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xF21B2030),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x55D4B886)),
      ),
      titleTextStyle: const TextStyle(
        color: AppColors.gold,
        fontSize: 19,
        letterSpacing: 2,
      ),
      contentTextStyle: const TextStyle(color: AppColors.text),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xF21B2030),
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: Color(0xF21B2030)),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(
        AppColors.goldDeep.withValues(alpha: 0.4),
      ),
    ),
  );
}
