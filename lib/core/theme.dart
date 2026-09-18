/// 主题与视觉规范：深空青金 + Material 3。
library;

import 'package:flutter/foundation.dart';
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

  final TextTheme rawBase = Typography.material2021(
    platform: defaultTargetPlatform,
  ).white;

  // 使用「系统自带字体」并显式给出中文栈：Windows 走微软雅黑，macOS 走苹方/系统默认，
  // 这样既符合各平台观感，也避免 Flutter 默认回退到日文字体把「点」画成竖画。
  final List<String> cjkSans = switch (defaultTargetPlatform) {
    TargetPlatform.windows => const <String>[
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'SimHei',
      'SimSun',
      'serif',
    ],
    TargetPlatform.macOS => const <String>[
      'PingFang SC',
      'Hiragino Sans GB',
      'Heiti SC',
      'STHeiti',
      'sans-serif',
    ],
    TargetPlatform.iOS => const <String>[
      'PingFang SC',
      'Heiti SC',
      'sans-serif',
    ],
    TargetPlatform.android => const <String>[
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'sans-serif',
    ],
    TargetPlatform.linux => const <String>[
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'WenQuanYi Micro Hei',
      'sans-serif',
    ],
    _ => const <String>[
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'PingFang SC',
      'Hiragino Sans GB',
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'WenQuanYi Micro Hei',
      'sans-serif',
    ],
  };

  /// 主字体：Windows 用微软雅黑，其余平台交给系统默认（再由 fallback 兜中文）。
  final String? primary = defaultTargetPlatform == TargetPlatform.windows
      ? 'Microsoft YaHei UI'
      : null;

  // 先给整套 TextTheme 打上字体与中文回退，确保没有漏网的样式（display/title/label 全覆盖）。
  final TextTheme base = rawBase.apply(
    fontFamily: primary,
    fontFamilyFallback: cjkSans,
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );

  TextStyle? sans(
    TextStyle? s, {
    Color? color,
    double? letterSpacing,
    FontWeight? weight,
  }) {
    return s?.copyWith(
      color: color,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      fontFamily: primary,
      fontFamilyFallback: cjkSans,
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.backdrop,
    fontFamily: primary,
    fontFamilyFallback: cjkSans,
    textTheme: base.copyWith(
      displaySmall: sans(
        base.displaySmall,
        color: AppColors.gold,
        letterSpacing: 4,
      ),
      headlineMedium: sans(
        base.headlineMedium,
        color: AppColors.gold,
        letterSpacing: 3,
        weight: FontWeight.w600,
      ),
      headlineSmall: sans(base.headlineSmall, color: AppColors.gold),
      titleLarge: sans(
        base.titleLarge,
        color: AppColors.gold,
        letterSpacing: 1.5,
      ),
      titleMedium: sans(base.titleMedium, color: AppColors.text),
      titleSmall: sans(base.titleSmall, color: AppColors.textMuted),
      bodyLarge: sans(base.bodyLarge, color: AppColors.text),
      bodyMedium: sans(base.bodyMedium, color: AppColors.text),
      bodySmall: sans(base.bodySmall, color: AppColors.textMuted),
      labelLarge: sans(base.labelLarge, letterSpacing: 1),
      labelMedium: sans(base.labelMedium),
      labelSmall: sans(base.labelSmall),
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
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: const Color(0xCC0C1426),
      indicatorColor: const Color(0x33F7E2A8),
      selectedIconTheme: const IconThemeData(color: AppColors.gold),
      unselectedIconTheme: const IconThemeData(color: AppColors.textFaint),
      selectedLabelTextStyle: TextStyle(
        color: AppColors.gold,
        letterSpacing: 1,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: AppColors.textMuted,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xF00C1426),
      indicatorColor: const Color(0x33F7E2A8),
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        TextStyle(
          fontSize: 12,
          color: AppColors.textMuted,
          fontFamily: primary,
          fontFamilyFallback: cjkSans,
        ),
      ),
      iconTheme: const WidgetStatePropertyAll<IconThemeData>(
        IconThemeData(color: AppColors.goldDeep),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.gold,
      titleTextStyle: TextStyle(
        color: AppColors.gold,
        fontSize: 20,
        letterSpacing: 3,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xF21B2030),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x55D4B886)),
      ),
      titleTextStyle: TextStyle(
        color: AppColors.gold,
        fontSize: 19,
        letterSpacing: 2,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
      contentTextStyle: TextStyle(
        color: AppColors.text,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xF21B2030),
      contentTextStyle: TextStyle(
        color: AppColors.text,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(color: Color(0xF21B2030)),
      textStyle: TextStyle(
        color: AppColors.text,
        fontSize: 12,
        fontFamily: primary,
        fontFamilyFallback: cjkSans,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(
        AppColors.goldDeep.withValues(alpha: 0.4),
      ),
    ),
  );
}
