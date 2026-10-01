import 'package:flutter/material.dart';

/// Вулик-поштомат на головному екрані (малюнок автора —
/// design/guide/hive_mailbox.pdf: бджола приносить лист, прапорець піднято).
/// Коли є важливі повідомлення (прострочені огляди, час докупити) — бджола
/// з листом і прапорцем + червоний значок кількості; пошти немає — порожній
/// вулик (hive_mailbox_empty.pdf). Обидва малюнки в одному кадрі.
class HivePostbox extends StatelessWidget {
  final int count;
  final double height;
  final VoidCallback? onTap;
  const HivePostbox({super.key, this.count = 0, this.height = 96, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = height * 0.55;
    return Semantics(
      button: onTap != null,
      label: count > 0 ? 'Вулик-поштомат: повідомлень $count' : 'Вулик-поштомат',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: height,
          width: w,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Image.asset(
                    count > 0
                        ? 'assets/guide/hive_mailbox.webp'
                        : 'assets/guide/hive_mailbox_empty.webp',
                    key: ValueKey(count > 0),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium),
              ),
            ),
            if (count > 0)
              Positioned(
                top: height * 0.18,
                left: -w * 0.08,
                child: Container(
                  constraints: BoxConstraints(minWidth: height * 0.22),
                  height: height * 0.22,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCD4C28),
                    borderRadius: BorderRadius.circular(height),
                    border: Border.all(color: const Color(0xFF3A2410), width: 2),
                  ),
                  child: Text(count > 9 ? '9+' : '$count',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: height * 0.13,
                          fontWeight: FontWeight.w800,
                          height: 1)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
