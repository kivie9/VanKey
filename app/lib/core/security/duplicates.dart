import '../errors.dart';
import '../vault/hlc.dart';
import '../vault/models.dart';

enum DuplicateKind {
  /// Cùng khóa 2FA.
  sameTotp,

  /// Cùng tên và cùng tài khoản.
  sameTitleAccount,

  /// Nhiều mục đăng nhập dùng chung một mật khẩu (chỉ cảnh báo, không gộp).
  sharedPassword,
}

final class DuplicateGroup {
  const DuplicateGroup(this.kind, this.items);

  final DuplicateKind kind;

  /// Mới nhất ở đầu.
  final List<Item> items;

  bool get canMerge => kind != DuplicateKind.sharedPassword;
}

String _account(Item i) => (i.valueOf('username') ?? i.valueOf('account') ?? '').trim();

int _newestFirst(Item a, Item b) {
  final c = b.updatedAt.compareTo(a.updatedAt);
  return c != 0 ? c : b.version.compareTo(a.version);
}

/// Tìm các mục trùng lặp (bỏ qua mục trong thùng rác).
List<DuplicateGroup> findDuplicates(Iterable<Item> all) {
  final items = all.where((i) => !i.inTrash).toList();
  final out = <DuplicateGroup>[];
  final seenSets = <String>{};

  void collect(DuplicateKind kind, String? Function(Item) key, {bool skipSeen = false}) {
    final m = <String, List<Item>>{};
    for (final i in items) {
      final k = key(i);
      if (k == null || k.isEmpty) continue;
      m.putIfAbsent(k, () => []).add(i);
    }
    for (final g in m.values) {
      if (g.length < 2) continue;
      g.sort(_newestFirst);
      final sig = (g.map((i) => i.id).toList()..sort()).join(',');
      if (skipSeen && seenSets.contains(sig)) continue;
      seenSets.add(sig);
      out.add(DuplicateGroup(kind, g));
    }
  }

  collect(DuplicateKind.sameTotp, (i) => i.totp?.secret.toUpperCase());
  collect(
    DuplicateKind.sameTitleAccount,
    (i) => _account(i).isEmpty ? null : '${i.title.trim().toLowerCase()}|${_account(i).toLowerCase()}',
    skipSeen: true,
  );
  // Mật khẩu dùng chung: chỉ xét mục đăng nhập có mật khẩu.
  collect(DuplicateKind.sharedPassword, (i) => i.type == ItemType.login ? i.password : null, skipSeen: true);
  return out;
}

/// Kết quả gộp một nhóm trùng.
final class MergeOutcome {
  const MergeOutcome({required this.kept, required this.trashed});

  /// Mục được giữ (đã bổ sung dữ liệu từ các mục bị gộp).
  final Item kept;

  /// Các mục bị gộp, đã chuyển vào thùng rác (khôi phục được).
  final List<Item> trashed;
}

/// Gộp một nhóm trùng: giữ bản mới nhất, **mang theo** khóa 2FA, nhóm, nhắc hạn, yêu thích nếu bản giữ lại còn thiếu,
/// và cất mật khẩu khác của các bản bị gộp vào lịch sử để không mất dữ liệu.
MergeOutcome mergeDuplicateGroup(DuplicateGroup g, {required HlcClock clock, DateTime? now}) {
  if (!g.canMerge) throw const InvalidInputException('không thể tự động gộp các mục chỉ trùng mật khẩu');
  final keep = g.items.first;
  final others = g.items.skip(1).toList();

  var totp = keep.totp;
  var group = keep.group;
  var reminder = keep.reminder;
  var favorite = keep.favorite;
  final history = <PwHistoryEntry>[...keep.pwHistory];
  final known = <String>{keep.password, ...history.map((h) => h.value)};
  for (final o in others) {
    totp ??= o.totp;
    if (group.isEmpty) group = o.group;
    reminder ??= o.reminder;
    favorite = favorite || o.favorite;
    for (final p in [o.password, ...o.pwHistory.map((h) => h.value)]) {
      if (p.isNotEmpty && known.add(p)) history.add(PwHistoryEntry(value: p, changedAt: o.updatedAt));
    }
  }

  final merged = keep.edit(clock: clock, totp: totp, group: group, reminder: reminder, favorite: favorite, now: now).copyWith(
    pwHistory: history.take(10).toList(),
  );
  return MergeOutcome(
    kept: merged,
    trashed: [for (final o in others) o.moveToTrash(clock: clock, now: now)],
  );
}
