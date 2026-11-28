import 'package:flutter/material.dart';

/// Єдина палітра застосунку: тепла темна "дерев'яна" пасіка з
/// оранжево-медовими акцентами (порт theme.py).
class AppColors {
  static Color _c(double r, double g, double b, [double a = 1]) =>
      Color.fromRGBO((r * 255).round(), (g * 255).round(), (b * 255).round(), a);

  static const qrLinked = Color(0xFF43C463); // зелений ободок: у вулика є QR-код
  static final bg = _c(0.114, 0.086, 0.067);
  static final bgLight = _c(0.157, 0.122, 0.094);
  static final panel = _c(0.098, 0.075, 0.059);
  static final roundBtn = _c(0.129, 0.098, 0.075);
  static final grass = _c(0.541, 0.671, 0.298);
  static final gridLine = _c(0.20, 0.14, 0.06, 0.5);
  static final hive = _c(0.929, 0.616, 0.184);
  static final obstacle = _c(0.596, 0.522, 0.412);
  static final objectBorder = _c(0.294, 0.173, 0.075, 0.9);
  static final accent = _c(0.722, 0.412, 0.098);
  static final create = _c(0.929, 0.616, 0.184);
  static final addObject = _c(0.557, 0.616, 0.239);
  static final danger = _c(0.804, 0.298, 0.157);
  /// Жовте попередження: сума чека не зійшлась, різницю винесено в «Корегування».
  static final caution = _c(0.976, 0.835, 0.255);
  static final rename = _c(0.694, 0.549, 0.243);
  static final text = _c(0.976, 0.937, 0.878);
  static final textMuted = _c(0.75, 0.68, 0.58);
  static final card = _c(0.098, 0.075, 0.059);
  static final popupBg = _c(0.145, 0.110, 0.086);
  static final frame = _c(0.06, 0.045, 0.035);
  static final input = _c(0.22, 0.17, 0.13);
  static final neutralBtn = _c(0.30, 0.24, 0.18);
  static final darkBtn = _c(0.20, 0.15, 0.11);
  static final typeBtn = _c(0.24, 0.19, 0.14);
  static final iconMark = _c(0.30, 0.17, 0.08, 0.85);
  static final warning = _c(0.804, 0.298, 0.157, 0.95);
  static final capsule = _c(0.35, 0.32, 0.28, 0.55);
  static final modeActive = _c(0.945, 0.482, 0.373);
}

/// Єдиний плавний перехід між екранами для всіх платформ: новий екран
/// м'яко з'являється й трохи під'їжджає справа, попередній - ледь зсувається
/// й тьмяніє. Криві без різких стартів і зупинок.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final enter = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final leave = secondaryAnimation.drive(CurveTween(curve: Curves.easeInOutCubic));
    return SlideTransition(
      position: leave.drive(Tween(begin: Offset.zero, end: const Offset(-0.04, 0))),
      child: FadeTransition(
        opacity: leave.drive(Tween(begin: 1.0, end: 0.9)),
        child: SlideTransition(
          position: enter.drive(Tween(begin: const Offset(0.07, 0), end: Offset.zero)),
          child: FadeTransition(opacity: enter, child: child),
        ),
      ),
    );
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    surface: AppColors.bg,
    onSurface: AppColors.text,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final p in TargetPlatform.values) p: const SmoothPageTransitionsBuilder(),
    }),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.popupBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.popupBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.popupBg,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 14),
      actionTextColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? AppColors.accent : AppColors.darkBtn),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? AppColors.accent : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: AppColors.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.create),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.accent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      labelStyle: TextStyle(color: AppColors.textMuted),
    ),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
        ),
  );
}
