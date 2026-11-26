import 'hlc.dart';
import 'models.dart';

/// Hai phiên bản khác nhau của cùng một mục, cả hai đã đổi so với bản chung gần nhất.
final class ItemConflict {
  const ItemConflict({required this.id, required this.local, required this.remote, required this.winner});

  final String id;
  final Item local;
  final Item remote;

  /// Bản đang được giữ trong kết quả gộp (bản có HLC lớn hơn). Giao diện cho người dùng chọn lại.
  final Item winner;
}

final class MergeResult {
  const MergeResult({required this.merged, required this.conflicts, required this.changesLocal, required this.changesRemote});

  final VaultData merged;
  final List<ItemConflict> conflicts;

  /// Kết quả gộp khác bản cục bộ (cần lưu cục bộ).
  final bool changesLocal;

  /// Kết quả gộp khác bản trên máy chủ (cần tải lên).
  final bool changesRemote;
}

enum ConflictChoice { keepLocal, keepRemote }

/// Trạng thái của một id ở một phía: có mục, đã xóa vĩnh viễn (tombstone), hoặc không có gì.
final class _State {
  const _State.item(Item this.item) : tomb = null;
  const _State.tomb(Tombstone this.tomb) : item = null;
  const _State.absent() : item = null, tomb = null;

  final Item? item;
  final Tombstone? tomb;

  bool get isAbsent => item == null && tomb == null;
  Hlc get version => item?.version ?? tomb?.version ?? Hlc.zero;
}

bool _same(_State a, _State b) {
  if (a.isAbsent && b.isAbsent) return true;
  if (a.item != null && b.item != null) return a.item!.hlc == b.item!.hlc;
  if (a.tomb != null && b.tomb != null) return true;
  return false;
}

Map<String, _State> _index(VaultData? d) {
  final out = <String, _State>{};
  if (d == null) return out;
  for (final t in d.tombstones) {
    out[t.id] = _State.tomb(t);
  }
  for (final i in d.items) {
    final cur = out[i.id];
    // Nếu dữ liệu có cả mục lẫn tombstone cho một id, giữ cái có HLC lớn hơn.
    if (cur == null || i.version.compareTo(cur.version) >= 0) out[i.id] = _State.item(i);
  }
  return out;
}

/// Gộp **ba chiều**: [local] và [remote] là hai bản hiện tại, [base] là bản chung gần nhất đã đồng bộ
/// (lưu lại sau mỗi lần đồng bộ thành công; `null` nếu chưa từng đồng bộ).
///
/// - Chỉ một bên đổi so với [base] → lấy bên đó, không xung đột (kể cả khi bên kia sửa nhiều lần liên tiếp).
/// - Cả hai bên đổi → bản có HLC lớn hơn thắng; nếu cả hai đều là mục còn tồn tại thì ghi nhận [ItemConflict]
///   để giao diện hỏi người dùng (không ghi đè âm thầm).
/// - Mục xóa vĩnh viễn (tombstone) đối đầu với bản sửa → bản có HLC lớn hơn thắng (sửa sau xóa thì giữ bản sửa).
/// - Vắng mặt (không có mục, không có tombstone) **không phải là xóa**: giữ bản của bên còn lại. Nhờ vậy một bản
///   cập nhật bị ghi đè mất trên nơi lưu không biến thành "xóa" ở các máy khác.
///
/// Kết quả **không phụ thuộc thứ tự** [local]/[remote] (giao hoán) và gộp lại kết quả với chính nó không đổi (lũy đẳng).
MergeResult mergeVaults({required VaultData local, required VaultData remote, VaultData? base}) {
  final l = _index(local);
  final r = _index(remote);
  final b = base == null ? null : _index(base);
  final ids = <String>{...l.keys, ...r.keys, if (b != null) ...b.keys};

  const absent = _State.absent();
  final mergedItems = <Item>[];
  final mergedTombs = <Tombstone>[];
  final conflicts = <ItemConflict>[];
  var changesLocal = false;
  var changesRemote = false;

  for (final id in ids) {
    final L = l[id] ?? absent;
    final R = r[id] ?? absent;
    final B = b == null ? null : (b[id] ?? absent);

    _State result;
    if (_same(L, R)) {
      // Hai tombstone cùng "đã xóa" nhưng có thể mang HLC khác nhau (cùng xóa trên hai máy):
      // chọn bản HLC lớn hơn để kết quả không phụ thuộc thứ tự local/remote.
      result = (L.tomb != null && R.tomb != null && R.version > L.version) ? R : L;
    } else if (L.isAbsent) {
      // VẮNG MẶT KHÔNG PHẢI XÓA: việc xóa luôn để lại tombstone (hoặc đưa vào thùng rác, là một phiên bản bình thường).
      // Một bên không có mục mà cũng không có tombstone nghĩa là bên đó chưa có, hoặc đã MẤT bản cập nhật (ví dụ nơi lưu
      // không có ghi có điều kiện nên hai máy ghi đè nhau). Giữ bản của bên còn lại, kể cả khi bản gốc có mục này.
      result = R;
    } else if (R.isAbsent) {
      result = L;
    } else if (B != null) {
      final lChanged = !_same(L, B);
      final rChanged = !_same(R, B);
      if (!lChanged) {
        result = R;
      } else if (!rChanged) {
        result = L;
      } else {
        result = _winner(L, R, conflicts, id);
      }
    } else {
      result = _winner(L, R, conflicts, id);
    }

    if (!_same(result, L)) changesLocal = true;
    if (!_same(result, R)) changesRemote = true;
    if (result.item != null) mergedItems.add(result.item!);
    if (result.tomb != null) mergedTombs.add(result.tomb!);
  }

  mergedItems.sort((a, b) => a.id.compareTo(b.id));
  mergedTombs.sort((a, b) => a.id.compareTo(b.id));
  conflicts.sort((a, b) => a.id.compareTo(b.id));

  final groups = <String>[
    ...local.groups,
    for (final g in remote.groups)
      if (!local.groups.contains(g)) g,
    for (final i in mergedItems)
      if (i.group.isNotEmpty && !local.groups.contains(i.group) && !remote.groups.contains(i.group)) i.group,
  ];
  final seen = <String>{};
  final uniqueGroups = [for (final g in groups) if (seen.add(g)) g];

  return MergeResult(
    merged: VaultData(
      schema: local.schema > remote.schema ? local.schema : remote.schema,
      groups: uniqueGroups,
      items: mergedItems,
      tombstones: mergedTombs,
      extra: {...remote.extra, ...local.extra},
    ),
    conflicts: conflicts,
    changesLocal: changesLocal,
    changesRemote: changesRemote,
  );
}

_State _winner(_State a, _State b, List<ItemConflict> conflicts, String id) {
  // Thứ tự toàn phần (ms, bộ đếm, id thiết bị) nên cả hai phía luôn chọn cùng một bản.
  final aWins = a.version.compareTo(b.version) >= 0;
  final win = aWins ? a : b;
  if (a.item != null && b.item != null) {
    conflicts.add(ItemConflict(id: id, local: a.item!, remote: b.item!, winner: win.item!));
  }
  return win;
}

/// Áp dụng lựa chọn của người dùng cho một xung đột: giữ nội dung đã chọn, tạo **phiên bản mới**
/// (HLC lớn hơn cả hai) để lần đồng bộ sau mọi thiết bị đều nhận bản này.
Item resolveConflict(ItemConflict c, ConflictChoice choice, {required HlcClock clock, DateTime? now}) {
  clock
    ..observe(c.local.version)
    ..observe(c.remote.version);
  final chosen = choice == ConflictChoice.keepLocal ? c.local : c.remote;
  return chosen.copyWith(updatedAt: (now ?? DateTime.now()).toUtc(), hlc: clock.next().toString());
}
