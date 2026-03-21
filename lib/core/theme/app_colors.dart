// lib/core/theme/app_colors.dart
// 豆包风格色彩系统 — 深邃暗色 + 彩虹渐变点缀
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── 背景层次（豆包深色）────────────────────────
  static const bg0       = Color(0xFF0F0F10);   // 最底层黑
  static const surface   = Color(0xFF161618);   // 主背景（豆包式偏蓝黑）
  static const surfaceL1 = Color(0xFF1C1C1E);   // 卡片背景（Apple系统灰）
  static const surfaceL2 = Color(0xFF242428);   // 次级卡片
  static const surfaceL3 = Color(0xFF2C2C30);   // 浮层背景

  // 向后兼容别名
  static const bg1    = surface;
  static const bg2    = surfaceL1;
  static const bg3    = surfaceL2;
  static const cardBg = surfaceL1;

  // ── 分割线 ─────────────────────────────────────
  static const divider  = Color(0xFF2A2A2E);
  static const border   = Color(0xFF3A3A40);
  static const line1    = divider;
  static const line2    = border;

  // ── 文字层次 ───────────────────────────────────
  static const textPrimary   = Color(0xFFE5E5EA);  // Apple label
  static const textSecondary = Color(0xFF98989F);  // Apple secondaryLabel
  static const textTertiary  = Color(0xFF6A6A6F);  // Apple tertiaryLabel
  static const text1  = textPrimary;
  static const text2  = textSecondary;
  static const text3  = textTertiary;

  // ── 主题色：豆包渐变紫蓝（强调色）────────────────
  static const accent        = Color(0xFF7C6FF7);  // 豆包主紫
  static const accentLight   = Color(0xFF9B8FFF);
  static const accentDark    = Color(0xFF5A50D4);
  static const accentDim     = Color(0x1A7C6FF7);

  // 渐变
  static const gradientPrimary = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF7C6FF7), Color(0xFF4FACFE)],
  );
  static const gradientWarm = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFFF9A56), Color(0xFFFF6B9D)],
  );
  static const gradientSuccess = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), Color(0xFF059669)],
  );

  // ── 功能色 ─────────────────────────────────────
  static const success  = Color(0xFF34D399);  // 绿
  static const warning  = Color(0xFFFBBF24);  // 黄
  static const error    = Color(0xFFFC5C7D);  // 红
  static const info     = Color(0xFF60A5FA);  // 蓝

  // Dim 版本
  static const successDim = Color(0x1A34D399);
  static const warningDim = Color(0x1AFBBF24);
  static const errorDim   = Color(0x1AFC5C7D);
  static const infoDim    = Color(0x1A60A5FA);

  // ── 兼容旧版颜色名 ─────────────────────────────
  static const gold      = Color(0xFFE8B840);
  static const gold2     = Color(0xFFF0C84A);
  static const goldDim   = Color(0x1AE8B840);
  static const jade2     = success;
  static const jadeDim   = successDim;
  static const crimson2  = error;
  static const crimsonDim = errorDim;
  static const blue2     = info;
  static const blueDim   = infoDim;
  static const purple2   = accent;
  static const purpleDim = accentDim;
  static const teal2     = Color(0xFF2DD4BF);
  static const orange2   = Color(0xFFFB923C);

  // ── 任务状态色 ─────────────────────────────────
  static Color taskColor(String s) => switch (s) {
    'PLANNING'      => info,     'REVIEWING'     => warning,
    'REJECTED'      => error,    'ASSIGNED'      => success,
    'EXECUTING'     => accent,   'AUDITING'      => teal2,
    'REVISING'      => orange2,  'PENDING_HUMAN' => warning,
    'DONE'          => success,  'BLOCKED'       => error,
    _               => textTertiary,
  };
}
