import 'package:flutter/material.dart';

/// Іконка застосунку на заставці й головному екрані: пасічник із рамкою
/// меду на кремовому тлі (як на телефоні; малюнок —
/// design/guide/beekeeper_honey_frame.pdf).
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 168});

  @override
  Widget build(BuildContext context) {
    final k = size / 168;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.fromLTRB(26 * k, 16 * k, 26 * k, 12 * k),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE9C4),
        borderRadius: BorderRadius.circular(38 * k),
      ),
      child: Image.asset('assets/guide/beekeeper_honey_frame.webp',
          filterQuality: FilterQuality.medium),
    );
  }
}
