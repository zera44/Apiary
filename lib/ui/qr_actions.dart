import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../screens/map_screen.dart';
import '../screens/qr_generate_screen.dart';
import 'app_drawer.dart';
import 'common.dart';

/// Дія-підпункт розкривного списку розділу (напр. «Сканувати» в QR-коді).
typedef NavAction = ({IconData icon, String label, VoidCallback onTap});

/// Дії розділу «QR-код»: Сканувати, Генерувати, Прив'язати. Окремого екрана в
/// розділу немає - вони розкриваються в меню ☰ і відкриваються поверх поточного екрана.
List<NavAction> qrActions(BuildContext context, Repository repo) {
  final nav = Navigator.of(context);

  Future<void> withApiary(Future<void> Function(dynamic apiary) go) async {
    final a =
        await repo.startApiary() ?? (await repo.listApiaries()).firstOrNull;
    if (a == null) {
      if (nav.mounted) await showInfo(nav.context, tr.qrCreateApiaryFirst);
      return;
    }
    if (nav.mounted) await go(a);
  }

  return [
    (
      icon: TablerIcons.scan,
      label: tr.scan,
      onTap: () => AppDrawer.openHiveByQr(nav, repo),
    ),
    (
      icon: TablerIcons.qrcode,
      label: tr.generate,
      onTap: () => withApiary(
        (a) => nav.push(
          MaterialPageRoute<void>(
            builder: (_) => QrGenerateScreen(repo: repo, apiary: a),
          ),
        ),
      ),
    ),
    (
      icon: TablerIcons.list_numbers,
      label: tr.qrBindRow,
      onTap: () => withApiary(
        (a) => nav.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                MapScreen(repo: repo, apiary: a, bindRowOnOpen: true),
          ),
        ),
      ),
    ),
  ];
}
