import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../l10n/l10n.dart';

/// Розділи «Налаштувань» (підпункти меню ☰).
enum SettingsPart {
  look(TablerIcons.palette),
  assistant(TablerIcons.robot),
  templates(TablerIcons.template),
  account(TablerIcons.user),
  data(TablerIcons.database),
  about(TablerIcons.info_circle);

  final IconData icon;
  const SettingsPart(this.icon);

  String get label => switch (this) {
        look => tr.settingsSecLook,
        assistant => tr.settingsSecAssistant,
        templates => tr.settingsTabTemplates,
        account => tr.settingsTabAccount,
        data => tr.settingsSecData,
        about => tr.settingsSecAbout,
      };
}
