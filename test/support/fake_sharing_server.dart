import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sharing.dart';
import 'package:apiary/services/sharing.dart';

/// Фейковий сервер спільного доступу: ті самі правила, що задаватимуть
/// правила доступу Supabase (етап 4) - запрошення бачить лише той, кому
/// воно; помічників - лише власник; прийняти може лише адресат; прийняття
/// створює учасників.
class FakeSharingServer {
  /// Зареєстровані користувачі: пошта -> id.
  final users = <String, String>{};
  final invitations = <String, Invitation>{};
  final members = <String, Member>{};

  /// Зв'язку немає - кожен запит падає.
  bool offline = false;

  void register(String uid, String email) => users[normalizeEmail(email)] = uid;

  /// Клієнт, що працює від імені [email].
  SharingApi as(String email) => _Client(this, users[normalizeEmail(email)]!, normalizeEmail(email));

  void _net() {
    if (offline) throw StateError('немає зв\'язку із сервером');
  }
}

class _Client implements SharingApi {
  final FakeSharingServer s;
  @override
  final String myUserId;
  @override
  final String myEmail;
  _Client(this.s, this.myUserId, this.myEmail);

  @override
  Future<String?> findUser(String email) async {
    s._net();
    return s.users[normalizeEmail(email)];
  }

  @override
  Future<void> createInvitation(Invitation inv) async {
    s._net();
    if (inv.fromUserId != myUserId) throw StateError('не від свого імені');
    s.invitations[inv.id] = inv;
  }

  @override
  Future<List<Invitation>> incoming() async {
    s._net();
    return [for (final i in s.invitations.values) if (i.toEmail == myEmail) i];
  }

  @override
  Future<List<Invitation>> outgoing() async {
    s._net();
    return [for (final i in s.invitations.values) if (i.fromUserId == myUserId) i];
  }

  @override
  Future<void> respond(String invitationId, {required bool accept}) async {
    s._net();
    final inv = s.invitations[invitationId];
    if (inv == null || inv.toEmail != myEmail) throw StateError('чуже запрошення');
    if (!inv.isPending) throw StateError('на запрошення вже відповіли');
    s.invitations[inv.id] = inv.withStatus(accept ? InviteStatus.accepted : InviteStatus.declined);
    if (!accept) return;
    for (final a in inv.apiaryIds ?? const <String?>[null]) {
      final id = Repository.newId();
      s.members[id] = Member(
        id: id,
        ownerId: inv.fromUserId,
        apiaryId: a,
        userId: myUserId,
        email: myEmail,
        stockAccess: inv.stockAccess,
        createdAt: Repository.now(),
      );
    }
  }

  @override
  Future<void> cancel(String invitationId) async {
    s._net();
    final inv = s.invitations[invitationId];
    if (inv == null || inv.fromUserId != myUserId) throw StateError('чуже запрошення');
    s.invitations[inv.id] = inv.withStatus(InviteStatus.revoked);
  }

  @override
  Future<List<Member>> members() async {
    s._net();
    return [for (final m in s.members.values) if (m.ownerId == myUserId) m];
  }

  @override
  Future<void> removeMember(String memberId) async {
    s._net();
    final m = s.members[memberId];
    if (m == null || m.ownerId != myUserId) throw StateError('чужий помічник');
    s.members.remove(memberId);
  }

  @override
  Future<void> setStockAccess(String memberId, {required bool on}) async {
    s._net();
    final m = s.members[memberId];
    if (m == null || m.ownerId != myUserId) throw StateError('чужий помічник');
    s.members[memberId] = m.withStockAccess(on);
  }
}
