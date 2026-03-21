// lib/widgets/common/widgets.dart
// 豆包风格 + 苹果交互 通用组件库
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';

// ════════════════════════════════════════════
// AppBadge — 豆包胶囊标签
// ════════════════════════════════════════════
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, required this.color, this.small = false});
  final String label;
  final Color  color;
  final bool   small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: small ? 6 : 8, vertical: small ? 2 : 4),
    decoration: BoxDecoration(
      color:        color.withOpacity(.12),
      borderRadius: BorderRadius.circular(small ? 4 : 6),
      border:       Border.all(color: color.withOpacity(.3), width: .5),
    ),
    child: Text(label, style: TextStyle(
      fontSize:      small ? 9 : 10,
      fontWeight:    FontWeight.w600,
      color:         color,
      letterSpacing: .3,
    )),
  );
}

// ════════════════════════════════════════════
// EmptyState — 豆包空态
// ════════════════════════════════════════════
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title,
    this.subtitle, this.action});
  final IconData  icon;
  final String    title;
  final String?   subtitle;
  final Widget?   action;

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(48),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color:  AppColors.surfaceL2,
          borderRadius: BorderRadius.circular(20)),
        child: Icon(icon, size: 32, color: AppColors.textTertiary),
      ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(.8,.8)),
      const SizedBox(height: 20),
      Text(title, style: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: AppColors.textSecondary))
        .animate(delay: 100.ms).fadeIn().slideY(begin: .2),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(subtitle!, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary, height: 1.6))
          .animate(delay: 150.ms).fadeIn(),
      ],
      if (action != null) ...[
        const SizedBox(height: 24),
        action!.animate(delay: 200.ms).fadeIn().slideY(begin: .3),
      ],
    ]),
  ));
}

// ════════════════════════════════════════════
// LoadingShimmer — 骨架屏
// ════════════════════════════════════════════
class LoadingShimmer extends StatelessWidget {
  const LoadingShimmer({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor:      AppColors.surfaceL2,
    highlightColor: AppColors.surfaceL3,
    child: ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceL2,
          borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

// ════════════════════════════════════════════
// SectionLabel — 分组标签
// ════════════════════════════════════════════
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = AppColors.textTertiary});
  final String text;
  final Color  color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
    child: Text(text, style: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600,
      color: color, letterSpacing: .5)),
  );
}

// ════════════════════════════════════════════
// NCard — 豆包风格卡片（圆角+轻边框）
// ════════════════════════════════════════════
class NCard extends StatelessWidget {
  const NCard({super.key, required this.child, this.padding, this.onTap,
    this.color, this.gradient, this.margin, this.radius = 16.0, this.border});
  final Widget  child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color:        Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap:        onTap,
          borderRadius: borderRadius,
          splashColor:  AppColors.accentDim,
          highlightColor: AppColors.surfaceL3.withOpacity(.5),
          child: Ink(
            decoration: BoxDecoration(
              color:        gradient == null ? (color ?? AppColors.surfaceL1) : null,
              gradient:     gradient,
              borderRadius: borderRadius,
              border:       border ?? Border.all(color: AppColors.divider, width: .5),
            ),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// GradientButton — 豆包渐变按钮
// ════════════════════════════════════════════
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.onPressed, required this.child,
    this.gradient, this.width, this.height = 50.0, this.radius = 14.0, this.enabled = true});
  final VoidCallback? onPressed;
  final Widget child;
  final LinearGradient? gradient;
  final double? width;
  final double  height;
  final double  radius;
  final bool    enabled;

  @override
  Widget build(BuildContext context) {
    final grad = gradient ?? AppColors.gradientPrimary;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        borderRadius: BorderRadius.circular(radius),
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () {
            HapticFeedback.lightImpact();
            onPressed?.call();
          } : null,
          borderRadius: BorderRadius.circular(radius),
          child: Ink(
            decoration: BoxDecoration(
              gradient: enabled ? grad : null,
              color:    enabled ? null : AppColors.surfaceL3,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// AsyncWidget — 统一的 AsyncValue 渲染
// ════════════════════════════════════════════
class AsyncWidget<T> extends StatelessWidget {
  const AsyncWidget({super.key, required this.value, required this.builder,
    this.loadingWidget, this.errorWidget});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Widget? loadingWidget;
  final Widget Function(Object error)? errorWidget;

  @override
  Widget build(BuildContext context) => value.when(
    data:    builder,
    loading: () => loadingWidget ?? const LoadingShimmer(),
    error:   (e, _) => errorWidget != null ? errorWidget!(e)
      : EmptyState(icon: Icons.error_outline_rounded, title: e.toString()),
  );
}

// ════════════════════════════════════════════
// NPill — 胶囊选择器（豆包Tab风格）
// ════════════════════════════════════════════
class NPill<T> extends StatelessWidget {
  const NPill({super.key, required this.options, required this.value, required this.onChanged,
    this.shrink = false});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final pills = options.map((opt) {
      final selected = opt.$1 == value;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(opt.$1);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color:        selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(opt.$2, style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color:     selected ? Colors.white : AppColors.textSecondary,
          )),
        ),
      );
    }).toList();

    final row = Row(
      mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
      children: pills,
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:        AppColors.surfaceL2,
        borderRadius: BorderRadius.circular(22),
        border:       Border.all(color: AppColors.border, width: .5),
      ),
      child: shrink ? row : row,
    );
  }
}

// ════════════════════════════════════════════
// InfoRow — 信息行（标签+值）
// ════════════════════════════════════════════
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value,
    this.valueColor, this.onTap});
  final String label;
  final String value;
  final Color?    valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      child: Row(children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const Spacer(),
        Text(value, style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: valueColor ?? AppColors.textPrimary,
        )),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
        ],
      ]),
    ),
  );
}

// ════════════════════════════════════════════
// ProgressRing — 圆环进度（朱雀分数用）
// ════════════════════════════════════════════
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.size,
    required this.color, this.strokeWidth = 6.0, this.child});
  final double value;      // 0.0-1.0
  final double size;
  final Color  color;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
        value:            value,
        strokeWidth:      strokeWidth,
        backgroundColor:  color.withOpacity(.15),
        valueColor:       AlwaysStoppedAnimation(color),
        strokeCap:        StrokeCap.round,
      ),
      if (child != null) child!,
    ]),
  );
}

// ════════════════════════════════════════════
// ProviderIcon — 供应商图标（Q2需求：自定义+自动识别）
// ════════════════════════════════════════════
class ProviderIcon extends StatelessWidget {
  const ProviderIcon({super.key, required this.baseUrl, this.size = 32.0});
  final String baseUrl;
  final double size;

  static final _iconMap = <String, (String, Color, Color)>{
    'deepseek.com':       ('🦋', Color(0xFF0052CC), Color(0xFF003D99)),
    'openai.com':         ('⬡',  Color(0xFF10A37F), Color(0xFF0D8A6A)),
    'anthropic.com':      ('◊',  Color(0xFFCC6633), Color(0xFFAA4422)),
    'dashscope.aliyuncs': ('通', Color(0xFFFF6A00), Color(0xFFE05500)),
    'volces.com':         ('豆', Color(0xFF4E6EF2), Color(0xFF3355E0)),
    'qianfan':            ('文', Color(0xFF2932E1), Color(0xFF1B24C0)),
    'minimax':            ('M',  Color(0xFF7B68EE), Color(0xFF6050DC)),
    'googleapis':         ('G',  Color(0xFF4285F4), Color(0xFF2B6AC2)),
    'siliconflow':        ('S',  Color(0xFF00C2C7), Color(0xFF00A0A5)),
    'together':           ('T',  Color(0xFF5E60CE), Color(0xFF4547C4)),
    'groq':               ('⚡', Color(0xFFF55036), Color(0xFFD03020)),
    'ollama':             ('🦙', Color(0xFF444654), Color(0xFF333544)),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _iconMap.entries.firstWhere(
      (e) => baseUrl.toLowerCase().contains(e.key),
      orElse: () => const MapEntry('', ('AI', Color(0xFF7C6FF7), Color(0xFF5A50D4))),
    );
    final (icon, start, end) = entry.value;
    final isEmoji = icon.length > 1 && !RegExp(r'^[A-Za-z0-9⬡◊⚡]$').hasMatch(icon);

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [start, end]),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Center(child: Text(icon, style: TextStyle(
        fontSize: isEmoji ? size * .45 : size * .4,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        fontFamily: isEmoji ? null : 'NotoSerifSC',
      ))),
    );
  }
}

// ════════════════════════════════════════════
// CalloutBox — 说明卡片
// ════════════════════════════════════════════
class CalloutBox extends StatelessWidget {
  const CalloutBox({super.key, required this.title, required this.children,
    this.color = AppColors.accent, this.icon});
  final String title;
  final List<String> children;
  final Color  color;
  final String? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        color.withOpacity(.08),
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: color.withOpacity(.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (icon != null) Text(icon!, style: const TextStyle(fontSize: 16)),
        if (icon != null) const SizedBox(width: 8),
        Text(title, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 8),
      ...children.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('·', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Expanded(child: Text(c, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary, height: 1.6))),
        ]),
      )),
    ]),
  );
}
