import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;

import '../data/repository.dart';
import '../data/sharing.dart';
import '../data/sync_service.dart';

/// Що вміє сервер для спільного доступу. Правила - на сервері (Row Level
/// Security, етап 4): запрошення бачить лише той, кому воно, помічників -
/// лише власник; прийняття створює учасників пасік. Справжня реалізація -
/// запити до Supabase (етап 5); у тестах - фейковий сервер.
abstract class SharingApi {
  /// Хто я (id і пошта на сервері).
  String get myUserId;
  String get myEmail;

  /// Користувач із такою поштою (id) або null - такого немає.
  Future<String?> findUser(String email);

  /// Надіслати запрошення.
  Future<void> createInvitation(Invitation inv);

  /// Запрошення на мою пошту (усі стани).
  Future<List<Invitation>> incoming();

  /// Надіслані мною.
  Future<List<Invitation>> outgoing();

  /// Прийняти чи відхилити (лише своє вхідне).
  Future<void> respond(String invitationId, {required bool accept});

  /// Скасувати своє надіслане запрошення.
  Future<void> cancel(String invitationId);

  /// Мої помічники (я - власник).
  Future<List<Member>> members();

  /// Забрати доступ.
  Future<void> removeMember(String memberId);

  /// Дати чи забрати склад і фінанси.
  Future<void> setStockAccess(String memberId, {required bool on});
}

/// Чим закінчилась спроба запросити.
enum InviteOutcome { sent, noSuchUser, alreadyHasAccess, self, invalidEmail, unavailable, failed }

/// Спільний доступ: запрошення й помічники. Звертається до сервера й
/// тримає копію в базі телефона (щоб показати й без інтернету).
class SharingService {
  /// Поточна служба (головний екран, «Мої пасіки»). Без сервера - [available] false.
  static SharingService current = SharingService(null, null);

  final SharingApi? api;
  final Repository? repo;

  /// Скільки вхідних запрошень чекає відповіді (значок на вулику-скриньці).
  final ValueNotifier<int> pending = ValueNotifier(0);

  SharingService(this.api, this.repo);

  /// Ділитися можна: сервер налаштовано й вхід виконано.
  bool get available => api != null && repo != null;

  /// Запросити помічника з поштою [email] до пасік [apiaryIds] (null -
  /// до всіх, зокрема майбутніх); [apiaryNames] - їхні назви для запрошення.
  Future<(InviteOutcome, String?)> invite(String email,
      {List<String>? apiaryIds, List<String> apiaryNames = const [], bool stockAccess = false}) async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return (InviteOutcome.unavailable, null);
    if (!looksLikeEmail(email)) return (InviteOutcome.invalidEmail, null);
    final to = normalizeEmail(email);
    if (to == normalizeEmail(api.myEmail)) return (InviteOutcome.self, null);
    try {
      final uid = await api.findUser(to);
      if (uid == null) return (InviteOutcome.noSuchUser, null);
      // уже має доступ до всіх чи до кожної з обраних
      final his = [for (final m in await api.members()) if (m.userId == uid) m];
      final hasAll = his.any((m) => m.apiaryId == null);
      final hasEach = apiaryIds != null &&
          apiaryIds.every((a) => his.any((m) => m.apiaryId == a)) &&
          his.every((m) => m.stockAccess || !stockAccess);
      if (hasAll || hasEach) return (InviteOutcome.alreadyHasAccess, null);
      final inv = Invitation(
        id: Repository.newId(),
        fromUserId: api.myUserId,
        fromEmail: api.myEmail,
        toEmail: to,
        apiaryIds: apiaryIds,
        apiaryNames: apiaryNames,
        stockAccess: stockAccess,
        createdAt: Repository.now(),
      );
      await api.createInvitation(inv);
      await repo.saveInvitations([inv]);
      return (InviteOutcome.sent, null);
    } catch (e) {
      debugPrint('Запрошення: $e');
      return (InviteOutcome.failed, '$e');
    }
  }

  /// Вхідні запрошення, що чекають відповіді. Без зв'язку - з копії.
  Future<List<Invitation>> incoming() async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return const [];
    try {
      await repo.saveInvitations(await api.incoming());
    } catch (e) {
      debugPrint('Запрошення (вхідні): $e');
    }
    final list = await repo.invitationsTo(api.myEmail);
    pending.value = list.length;
    return list;
  }

  /// Прийняти чи відхилити. Прийняли - пасіки з'являться після синхронізації.
  Future<void> respond(Invitation inv, {required bool accept}) async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return;
    await api.respond(inv.id, accept: accept);
    await repo.saveInvitations(
        [inv.withStatus(accept ? InviteStatus.accepted : InviteStatus.declined)]);
    pending.value = (await repo.invitationsTo(api.myEmail)).length;
    if (accept) await SyncService.now();
  }

  /// Мої помічники. Без зв'язку - з копії.
  Future<List<Member>> helpers() async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return const [];
    try {
      await repo.replaceMembers(await api.members());
    } catch (e) {
      debugPrint('Помічники: $e');
    }
    return repo.members();
  }

  /// Надіслані мною запрошення, що ще чекають відповіді.
  Future<List<Invitation>> sent() async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return const [];
    try {
      await repo.saveInvitations(await api.outgoing());
    } catch (e) {
      debugPrint('Запрошення (надіслані): $e');
    }
    return repo.invitationsFrom(api.myUserId);
  }

  /// Скасувати надіслане запрошення.
  Future<void> cancel(Invitation inv) async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return;
    await api.cancel(inv.id);
    await repo.saveInvitations([inv.withStatus(InviteStatus.revoked)]);
  }

  /// Забрати доступ у помічника.
  Future<void> revoke(Member m) async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return;
    await api.removeMember(m.id);
    await repo.replaceMembers([for (final x in await repo.members()) if (x.id != m.id) x]);
  }

  /// Дати чи забрати склад і фінанси.
  Future<void> setStockAccess(Member m, {required bool on}) async {
    final api = this.api, repo = this.repo;
    if (api == null || repo == null) return;
    await api.setStockAccess(m.id, on: on);
    await repo.replaceMembers(
        [for (final x in await repo.members()) x.id == m.id ? x.withStockAccess(on) : x]);
  }
}
