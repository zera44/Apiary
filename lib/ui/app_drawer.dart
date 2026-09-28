import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../screens/parameters_screen.dart';
import '../screens/templates_screen.dart';
import 'icons.dart';
import 'theme.dart';

/// Бічне меню (відкривається трьома смужками): Головна / Шаблони /
/// Характеристики.
class AppDrawer extends StatelessWidget {
  final Repository repo;
  const AppDrawer({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Моя пасіка',
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          _item(context, 'beehive', 'Головна', () {
            nav.pop(); // закрити меню
            nav.popUntil((r) => r.isFirst);
          }),
          _item(context, 'hexagon', 'Шаблони', () {
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => TemplatesScreen(repo: repo)));
          }),
          _item(context, 'history', 'Характеристики', () {
            nav.pop();
            nav.push(MaterialPageRoute(
              builder: (_) => ParametersScreen.forTemplate(repo: repo, initialIds: const [], elType: null),
            ));
          }),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, String icon, String text, VoidCallback onTap) {
    return ListTile(
      leading: AppIcon(icon, color: AppColors.text, size: 30),
      title: Text(text, style: TextStyle(color: AppColors.text, fontSize: 16)),
      onTap: onTap,
    );
  }
}
