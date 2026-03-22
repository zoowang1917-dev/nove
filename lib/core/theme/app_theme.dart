// lib/core/theme/app_theme.dart
// 豆包深色风格 + 苹果圆角交互 主题
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    colorScheme: const ColorScheme.dark(
      brightness:     Brightness.dark,
      primary:        AppColors.accent,
      secondary:      AppColors.teal2,
      surface:        AppColors.surfaceL1,
      error:          AppColors.error,
      onPrimary:      Colors.white,
      onSurface:      AppColors.textPrimary,
      outline:        AppColors.border,
      outlineVariant: AppColors.divider,
    ),
    textTheme:          _textTheme(),
    appBarTheme:        _appBarTheme(),
    navigationBarTheme: _navBarTheme(),
    cardTheme:          _cardTheme(),
    inputDecorationTheme: _inputTheme(),
    elevatedButtonTheme:  _elevatedBtnTheme(),
    outlinedButtonTheme:  _outlinedBtnTheme(),
    textButtonTheme:      _textBtnTheme(),
    tabBarTheme:        _tabTheme(),
    dividerTheme:       const DividerThemeData(color: AppColors.divider, thickness: .5, space: 1),
    iconTheme:          const IconThemeData(color: AppColors.textSecondary, size: 22),
    bottomSheetTheme:   _sheetTheme(),
    dialogTheme:        _dialogTheme(),
    chipTheme:          _chipTheme(),
    switchTheme:        _switchTheme(),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent, linearTrackColor: AppColors.divider),
    snackBarTheme:      _snackBarTheme(),
    listTileTheme:      _listTileTheme(),
    checkboxTheme:      _checkboxTheme(),
  );

  // ── AppBar ─────────────────────────────────────
  static AppBarTheme _appBarTheme() => AppBarTheme(
    backgroundColor:          AppColors.surface,
    surfaceTintColor:         Colors.transparent,
    elevation:                0,
    scrolledUnderElevation:   0,
    titleTextStyle: GoogleFonts.notoSansSc(
      fontSize: 17, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: .2),
    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
    actionsIconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
    systemOverlayStyle: const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
    ),
  );

  // ── 底部导航（豆包6Tab风格）────────────────────
  static NavigationBarThemeData _navBarTheme() => NavigationBarThemeData(
    backgroundColor:  AppColors.surfaceL1,
    surfaceTintColor: Colors.transparent,
    elevation:        0,
    height:           64,
    indicatorColor:   AppColors.accentDim,
    indicatorShape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
      color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textTertiary,
      size: 22,
    )),
    labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
      fontFamily: 'system',
      fontSize: 10,
      fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
      color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textTertiary,
      letterSpacing: .2,
    )),
  );

  // ── 卡片（Apple 圆角卡片）──────────────────────
  static CardTheme _cardTheme() => CardTheme(
    color:           AppColors.surfaceL1,
    elevation:       0,
    shape:           RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side:         const BorderSide(color: AppColors.divider, width: .5),
    ),
    margin:          EdgeInsets.zero,
  );

  // ── 输入框（豆包圆角风格）──────────────────────
  static InputDecorationTheme _inputTheme() {
    final radius = BorderRadius.circular(12);
    return InputDecorationTheme(
      filled:      true,
      fillColor:   AppColors.surfaceL2,
      border:      OutlineInputBorder(borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.border, width: .5)),
      enabledBorder: OutlineInputBorder(borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.border, width: .5)),
      focusedBorder: OutlineInputBorder(borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
      errorBorder:   OutlineInputBorder(borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.error, width: 1)),
      hintStyle:   GoogleFonts.notoSansSc(
        fontSize: 14, color: AppColors.textTertiary, fontWeight: FontWeight.w300),
      labelStyle:  GoogleFonts.notoSansSc(fontSize: 13, color: AppColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    );
  }

  // ── 主按钮（豆包渐变按钮）──────────────────────
  static ElevatedButtonThemeData _elevatedBtnTheme() => ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) ? AppColors.surfaceL3 : AppColors.accent),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      elevation:       WidgetStateProperty.all(0),
      shape:           WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      textStyle: WidgetStateProperty.all(GoogleFonts.notoSansSc(
        fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: .3)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
      overlayColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.pressed) ? Colors.white.withOpacity(.1) : null),
      animationDuration: const Duration(milliseconds: 150),
    ),
  );

  // ── 边框按钮 ────────────────────────────────────
  static OutlinedButtonThemeData _outlinedBtnTheme() => OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.accent,
      side: const BorderSide(color: AppColors.accent, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.notoSansSc(fontSize: 14, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
  );

  // ── 文字按钮 ────────────────────────────────────
  static TextButtonThemeData _textBtnTheme() => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: GoogleFonts.notoSansSc(fontSize: 14, fontWeight: FontWeight.w500),
    ),
  );

  // ── TabBar ──────────────────────────────────────
  static TabBarTheme _tabTheme() => TabBarTheme(
    indicatorColor:      AppColors.accent,
    indicatorSize:       TabBarIndicatorSize.label,
    labelColor:          AppColors.accent,
    unselectedLabelColor: AppColors.textTertiary,
    labelStyle:          GoogleFonts.notoSansSc(fontSize: 13, fontWeight: FontWeight.w600),
    unselectedLabelStyle: GoogleFonts.notoSansSc(fontSize: 13, fontWeight: FontWeight.w400),
    dividerColor:        AppColors.divider,
    tabAlignment:        TabAlignment.fill,
    overlayColor:        WidgetStateProperty.all(AppColors.accentDim),
  );

  // ── BottomSheet（苹果圆角底部弹出）──────────────
  static BottomSheetThemeData _sheetTheme() => const BottomSheetThemeData(
    backgroundColor:    AppColors.surfaceL1,
    surfaceTintColor:   Colors.transparent,
    elevation:          24,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(
      top: Radius.circular(20))),
    showDragHandle:     true,
    dragHandleColor:    AppColors.border,
    dragHandleSize:     Size(36, 4),
  );

  // ── Dialog ──────────────────────────────────────
  static DialogTheme _dialogTheme() => DialogTheme(
    backgroundColor: AppColors.surfaceL1,
    surfaceTintColor: Colors.transparent,
    elevation: 16,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    titleTextStyle: GoogleFonts.notoSansSc(
      fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    contentTextStyle: GoogleFonts.notoSansSc(
      fontSize: 14, color: AppColors.textSecondary, height: 1.6),
  );

  // ── Chip ────────────────────────────────────────
  static ChipThemeData _chipTheme() => ChipThemeData(
    backgroundColor: AppColors.surfaceL2,
    selectedColor:   AppColors.accentDim,
    side:            const BorderSide(color: AppColors.border, width: .5),
    shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    labelStyle:      GoogleFonts.notoSansSc(fontSize: 12, color: AppColors.textSecondary),
    padding:         const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    checkmarkColor:  AppColors.accent,
  );

  // ── Switch ──────────────────────────────────────
  static SwitchThemeData _switchTheme() => SwitchThemeData(
    thumbColor:  WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? Colors.white : AppColors.textTertiary),
    trackColor:  WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? AppColors.accent : AppColors.surfaceL3),
    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
  );

  // ── SnackBar ────────────────────────────────────
  static SnackBarThemeData _snackBarTheme() => SnackBarThemeData(
    backgroundColor:    AppColors.surfaceL3,
    contentTextStyle:   GoogleFonts.notoSansSc(fontSize: 13, color: AppColors.textPrimary),
    shape:              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    behavior:           SnackBarBehavior.floating,
    elevation:          8,
  );

  // ── ListTile ────────────────────────────────────
  static ListTileThemeData _listTileTheme() => ListTileThemeData(
    tileColor:          Colors.transparent,
    selectedColor:      AppColors.accent,
    iconColor:          AppColors.textSecondary,
    titleTextStyle:     GoogleFonts.notoSansSc(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w400),
    subtitleTextStyle:  GoogleFonts.notoSansSc(fontSize: 12, color: AppColors.textSecondary),
    contentPadding:     const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    shape:              RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
    minLeadingWidth:    24,
  );

  // ── Checkbox ────────────────────────────────────
  static CheckboxThemeData _checkboxTheme() => CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? AppColors.accent : Colors.transparent),
    checkColor: WidgetStateProperty.all(Colors.white),
    side: const BorderSide(color: AppColors.border, width: 1.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  );

  // ── TextTheme ───────────────────────────────────
  static TextTheme _textTheme() {
    final sc  = GoogleFonts.notoSansSc;
    return TextTheme(
      displayLarge:  const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 34,
        fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: .5),
      displayMedium: const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 26,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      displaySmall:  const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 20,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      headlineLarge:  sc(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      headlineMedium: sc(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      headlineSmall:  sc(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      titleLarge:   sc(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      titleMedium:  sc(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      titleSmall:   sc(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
      bodyLarge:    sc(fontSize: 16, fontWeight: FontWeight.w300, color: AppColors.textPrimary, height: 1.8),
      bodyMedium:   sc(fontSize: 14, fontWeight: FontWeight.w300, color: AppColors.textPrimary, height: 1.75),
      bodySmall:    sc(fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.textSecondary, height: 1.65),
      labelLarge:   sc(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
      labelMedium:  sc(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textTertiary, letterSpacing: .4),
      labelSmall:   sc(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.textTertiary, letterSpacing: .6),
    );
  }
}
