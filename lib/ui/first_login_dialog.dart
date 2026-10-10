import 'package:flutter/material.dart';

import '../data/first_login.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'theme.dart';

/// Що людина вибрала у вікні першого входу (null - вийти з акаунта).
typedef FirstLoginAnswer = ({FirstLoginChoice? choice, bool signOut});

/// Вікно першого входу: дані є і на телефоні, і на сервері (або на
/// телефоні - дані іншого акаунта). Закрити, не вибравши, не можна - до
/// вибору синхронізація чекає. Небезпечні варіанти - з підтвердженням.
Future<FirstLoginAnswer?> showFirstLoginDialog(BuildContext context, FirstLoginState state) async {
  final other = state == FirstLoginState.otherAccount;
  for (;;) {
    final picked = await showDialog<FirstLoginAnswer>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Widget option(String text, String? hint, Color bg, FirstLoginAnswer a, {Color fg = Colors.white}) =>
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PillButton(text: text, bg: bg, fg: fg, height: 44, onPressed: () => Navigator.pop(ctx, a)),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Text(hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ),
              ]),
            );
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.popupBg,
            title: Text(other ? tr.otherAccountTitle : tr.firstLoginTitle,
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(other ? tr.otherAccountText : tr.firstLoginText,
                    style: TextStyle(color: AppColors.text, fontSize: 14.5)),
                if (other) ...[
                  option(tr.otherAccountReplace, tr.firstLoginKeepServerHint, AppColors.accent,
                      (choice: FirstLoginChoice.keepServer, signOut: false)),
                  option(tr.otherAccountSignOut, null, AppColors.darkBtn, (choice: null, signOut: true),
                      fg: AppColors.text),
                ] else ...[
                  option(tr.firstLoginMerge, tr.firstLoginMergeHint, AppColors.accent,
                      (choice: FirstLoginChoice.merge, signOut: false)),
                  option(tr.firstLoginKeepPhone, tr.firstLoginKeepPhoneHint, AppColors.darkBtn,
                      (choice: FirstLoginChoice.keepPhone, signOut: false),
                      fg: AppColors.text),
                  option(tr.firstLoginKeepServer, tr.firstLoginKeepServerHint, AppColors.darkBtn,
                      (choice: FirstLoginChoice.keepServer, signOut: false),
                      fg: AppColors.text),
                ],
              ]),
            ),
          ),
        );
      },
    );
    if (picked == null || !context.mounted) return picked;
    final confirm = switch (picked.choice) {
      FirstLoginChoice.keepPhone => tr.firstLoginKeepPhoneConfirm,
      FirstLoginChoice.keepServer => tr.firstLoginKeepServerConfirm,
      _ => null,
    };
    if (confirm == null) return picked;
    final ok = await showConfirm(context,
        title: other ? tr.otherAccountTitle : tr.firstLoginTitle,
        text: confirm,
        confirmText: picked.choice == FirstLoginChoice.keepPhone ? tr.firstLoginKeepPhone : tr.firstLoginKeepServer,
        cancelText: tr.cancel);
    if (ok) return picked;
    if (!context.mounted) return null;
    // передумали - знову вибір
  }
}
