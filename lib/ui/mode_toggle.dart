import 'package:flutter/material.dart';

import 'theme.dart';

/// Розміри й місце перемикача режимів (унизу ліворуч).
const double kToggleSegW = 64, kToggleSegH = 46, kTogglePad = 4;
const double kToggleW = kToggleSegW * 2 + kTogglePad * 2 + 2;
const double kToggleH = kToggleSegH + kTogglePad * 2 + 2;
const double kToggleLeft = 14;

/// Урок: перемикач стоїть на одному місці в обох режимах — на ньому
/// спирається пасічник.
const double kToggleLessonBottom = 22;

/// Перемикач «Робочий режим / Редагування» з рухомим медовим повзунком.
/// Без [onWork]/[onEdit] — лише малюнок (у вікнах уроку під пасічником).
class ModeToggle extends StatelessWidget {
  final bool editing;
  final VoidCallback? onWork;
  final VoidCallback? onEdit;

  /// Лише малюнок (без підказок і натискань).
  final bool decorative;
  const ModeToggle(
      {super.key, required this.editing, this.onWork, this.onEdit, this.decorative = false});

  @override
  Widget build(BuildContext context) {
    Widget seg(String tip, IconData icon, bool on) =>
        decorative ? _segBody(icon, on) : Tooltip(message: tip, child: _segBody(icon, on));
    // тап будь-де по перемикачу — інший режим
    final tap = editing ? onWork : onEdit;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: decorative ? null : tap,
      child: Container(
      padding: const EdgeInsets.all(kTogglePad),
      decoration: BoxDecoration(
        color: AppColors.roundBtn,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(children: [
        // рухомий «повзунок» під активним режимом
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: editing ? kToggleSegW : 0,
          top: 0,
          width: kToggleSegW,
          height: kToggleSegH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(AppColors.accent, Colors.white, 0.22)!, AppColors.accent],
              ),
              boxShadow: [
                BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          seg('Робочий режим', Icons.visibility_outlined, !editing),
          seg('Редагування', Icons.edit_outlined, editing),
        ]),
      ]),
      ),
    );
  }

  Widget _segBody(IconData icon, bool on) => SizedBox(
        width: kToggleSegW,
        height: kToggleSegH,
        child: Center(
          child: AnimatedScale(
            scale: on ? 1.12 : 1,
            duration: const Duration(milliseconds: 200),
            child: Icon(icon, size: 24, color: on ? Colors.white : AppColors.textMuted),
          ),
        ),
      );
}
