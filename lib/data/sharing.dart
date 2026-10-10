import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'repository.dart';

/// Стан запрошення.
abstract final class InviteStatus {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const revoked = 'revoked';
}

/// Запрошення помічника: від кого, кому (пошта Google), на які пасіки
/// ([apiaryIds] null - усі, зокрема майбутні) і чи разом зі складом і
/// фінансами.
class Invitation {
  final String id;
  final String fromUserId;
  final String fromEmail;
  final String fromName;
  final String toEmail;
  final List<String>? apiaryIds;

  /// Назви пасік (щоб помічник бачив, куди його кличуть, ще до доступу).
  final List<String> apiaryNames;
  final bool stockAccess;
  final String status;
  final double createdAt;

  const Invitation({
    required this.id,
    required this.fromUserId,
    required this.fromEmail,
    this.fromName = '',
    required this.toEmail,
    this.apiaryIds,
    this.apiaryNames = const [],
    this.stockAccess = false,
    this.status = InviteStatus.pending,
    required this.createdAt,
  });

  bool get allApiaries => apiaryIds == null;
  bool get isPending => status == InviteStatus.pending;

  Invitation withStatus(String s) => Invitation(
        id: id,
        fromUserId: fromUserId,
        fromEmail: fromEmail,
        fromName: fromName,
        toEmail: toEmail,
        apiaryIds: apiaryIds,
        apiaryNames: apiaryNames,
        stockAccess: stockAccess,
        status: s,
        createdAt: createdAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'from_user_id': fromUserId,
        'from_email': fromEmail,
        'from_name': fromName,
        'to_email': toEmail,
        'apiary_ids': apiaryIds == null ? null : jsonEncode(apiaryIds),
        'apiary_names': jsonEncode(apiaryNames),
        'stock_access': stockAccess ? 1 : 0,
        'status': status,
        'created_at': createdAt,
      };

  factory Invitation.fromRow(Map<String, Object?> r) => Invitation(
        id: r['id']! as String,
        fromUserId: (r['from_user_id'] as String?) ?? '',
        fromEmail: (r['from_email'] as String?) ?? '',
        fromName: (r['from_name'] as String?) ?? '',
        toEmail: r['to_email']! as String,
        apiaryIds: r['apiary_ids'] == null ? null : _strings(r['apiary_ids'] as String),
        apiaryNames: _strings(r['apiary_names'] as String?),
        stockAccess: r['stock_access'] == 1,
        status: (r['status'] as String?) ?? InviteStatus.pending,
        createdAt: ((r['created_at'] as num?) ?? 0).toDouble(),
      );
}

/// Помічник власника: бачить пасіку [apiaryId] (null - усі пасіки
/// власника, зокрема майбутні); [stockAccess] - ще й склад і фінанси.
class Member {
  final String id;
  final String ownerId;
  final String? apiaryId;
  final String userId;
  final String email;
  final String role;
  final bool stockAccess;
  final double createdAt;

  const Member({
    required this.id,
    required this.ownerId,
    this.apiaryId,
    required this.userId,
    required this.email,
    this.role = 'helper',
    this.stockAccess = false,
    required this.createdAt,
  });

  Member withStockAccess(bool on) => Member(
        id: id,
        ownerId: ownerId,
        apiaryId: apiaryId,
        userId: userId,
        email: email,
        role: role,
        stockAccess: on,
        createdAt: createdAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        // свої помічники: власник - цей телефон (NULL)
        'owner_id': null,
        'apiary_id': apiaryId,
        'user_id': userId,
        'email': email,
        'role': role,
        'stock_access': stockAccess ? 1 : 0,
        'created_at': createdAt,
      };

  factory Member.fromRow(Map<String, Object?> r, {String ownerId = ''}) => Member(
        id: r['id']! as String,
        ownerId: (r['owner_id'] as String?) ?? ownerId,
        apiaryId: r['apiary_id'] as String?,
        userId: (r['user_id'] as String?) ?? '',
        email: r['email']! as String,
        role: (r['role'] as String?) ?? 'helper',
        stockAccess: r['stock_access'] == 1,
        createdAt: ((r['created_at'] as num?) ?? 0).toDouble(),
      );
}

List<String> _strings(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [for (final x in jsonDecode(raw) as List) x as String];
  } catch (_) {
    return const [];
  }
}

/// Пошта - так, як її порівнює сервер (без пробілів, малими літерами).
String normalizeEmail(String s) => s.trim().toLowerCase();

/// Схоже на адресу пошти.
bool looksLikeEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

/// Запрошення й помічники - копія того, що на сервері (щоб показати й
/// без інтернету). Ними керує сервер (окремими запитами), тому в черзі
/// звичайної синхронізації їх немає.
extension RepositorySharing on Repository {
  Future<void> saveInvitations(Iterable<Invitation> list) async {
    final t = Repository.now();
    await db.transaction((txn) async {
      for (final inv in list) {
        await txn.insert(
            'invitations', {...inv.toRow(), 'deleted': 0, 'updated_at': t, 'synced': 1},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Вхідні запрошення на пошту [email] (за замовчуванням - лише очікують).
  Future<List<Invitation>> invitationsTo(String email, {bool pendingOnly = true}) async {
    final rows = await db.query('invitations',
        where: 'deleted = 0 AND to_email = ?${pendingOnly ? ' AND status = ?' : ''}',
        whereArgs: [normalizeEmail(email), if (pendingOnly) InviteStatus.pending],
        orderBy: 'created_at DESC');
    return rows.map(Invitation.fromRow).toList();
  }

  /// Надіслані мною (користувачем [userId]) запрошення, що ще чекають.
  Future<List<Invitation>> invitationsFrom(String userId) async {
    final rows = await db.query('invitations',
        where: 'deleted = 0 AND from_user_id = ? AND status = ?',
        whereArgs: [userId, InviteStatus.pending],
        orderBy: 'created_at DESC');
    return rows.map(Invitation.fromRow).toList();
  }

  /// Замінити копію моїх помічників тим, що повернув сервер.
  Future<void> replaceMembers(List<Member> list) async {
    final t = Repository.now();
    await db.transaction((txn) async {
      await txn.delete('apiary_members', where: 'owner_id IS NULL');
      for (final m in list) {
        await txn.insert('apiary_members', {...m.toRow(), 'deleted': 0, 'updated_at': t, 'synced': 1},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Мої помічники (копія з сервера).
  Future<List<Member>> members() async {
    final rows = await db.query('apiary_members',
        where: 'deleted = 0 AND owner_id IS NULL', orderBy: 'email, created_at');
    return rows.map(Member.fromRow).toList();
  }
}
