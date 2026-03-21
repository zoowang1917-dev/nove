// lib/core/utils/extensions.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ── String 扩展 ─────────────────────────────────
extension StringX on String {
  int get chineseCount =>
      RegExp(r'[\u4e00-\u9fa5]').allMatches(this).length;

  String get wordCountLabel {
    final n = chineseCount;
    return n >= 10000 ? '${(n / 10000).toStringAsFixed(1)}万字' : '$n字';
  }

  String truncate(int max) => length > max ? '${substring(0, max)}...' : this;

  // F3 修复：安全获取首字符（替代 .characters.take(1).string）
  String get firstChar => isEmpty ? '' : this[0];
}

// ── int 扩展（F5 修复：int 上没有 wordCountLabel）──
extension IntX on int {
  String get wordCountLabel =>
      this >= 10000 ? '${(this / 10000).toStringAsFixed(1)}万字' : '$this字';
}

// ── DateTime 扩展 ────────────────────────────────
extension DateTimeX on DateTime {
  String get relative {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60)  return '刚刚';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24)    return '${diff.inHours}小时前';
    if (diff.inDays < 7)      return '${diff.inDays}天前';
    return '$month/$day';
  }
  String get ymd => '$year/$month/$day';
  String get hm  =>
      '${hour.toString().padLeft(2, "0")}:${minute.toString().padLeft(2, "0")}';
}

// ── BuildContext 扩展 ────────────────────────────
extension ContextX on BuildContext {
  double get screenWidth  => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  EdgeInsets get padding  => MediaQuery.of(this).padding;
  bool get isTablet       => screenWidth >= 600;

  void showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color ?? AppColors.bg3,
      duration: const Duration(seconds: 3),
    ));
  }
  // F5 修复：AppColors.crimson → AppColors.crimson2，AppColors.jade → AppColors.jade2
  void showError(String msg)   => showSnack(msg, color: AppColors.crimson2);
  void showSuccess(String msg) => showSnack(msg, color: AppColors.jade2);
}

// ── Color 扩展 ──────────────────────────────────
extension ColorX on Color {
  Color get dim8  => withOpacity(0.08);
  Color get dim12 => withOpacity(0.12);
  Color get dim30 => withOpacity(0.30);
  Color get dim50 => withOpacity(0.50);
}
