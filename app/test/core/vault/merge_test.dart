import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/merge.dart';
import 'package:vankey/core/vault/models.dart';

import '../../helpers/helpers.dart';

/// Giờ chung của "thế giới" thử nghiệm: mỗi lần hỏi tăng 1 ms, nên mọi thao tác có thứ tự thời gian rõ ràng.
int _world = 1000;
int _now() => _world += 1;

HlcClock device(String node) => HlcClock(node: node, nowMs: _now);

/// Chữ ký của một kho: id → phiên bản (mục) hoặc "T:" + phiên bản (tombstone). Dùng để so sánh kết quả gộp.
Map<String, String> sig(VaultData d) => {
      for (final i in d.items) i.id: i.hlc,
      for (final t in d.tombstones) t.id: 'T:${t.hlc}',
    };

Set<String> conflictIds(MergeResult r) => r.conflicts.map((c) => c.id).toSet();

VaultData vault(Iterable<Item> items, [Iterable<Tombstone> tombs = const []]) =>
    VaultData(items: items.toList(), tombstones: tombs.toList());

Item mk(HlcClock c, String title, SeededRandom rnd, {String group = ''}) =>
    Item.create(type: ItemType.login, title: title, clock: c, values: {'username': title}, group: group, random: rnd);

void main() {
  late HlcClock a;
  late HlcClock b;
  late SeededRandom rnd;

  setUp(() {
    _world = 1000;
    a = device('A');
    b = device('B');
    rnd = SeededRandom(1);
  });

  group('gộp ba chiều', () {
    test('không ai đổi gì → không thay đổi, không xung đột', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final r = mergeVaults(local: base, remote: base, base: base);
      expect(sig(r.merged), sig(base));
      expect(r.conflicts, isEmpty);
      expect(r.changesLocal, isFalse);
      expect(r.changesRemote, isFalse);
    });

    test('chỉ máy này sửa → lấy bản của máy này, cần tải lên, không xung đột', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final edited = x.edit(clock: a, title: 'x2');
      final r = mergeVaults(local: vault([edited]), remote: base, base: base);
      expect(r.merged.items.single.title, 'x2');
      expect(r.conflicts, isEmpty);
      expect(r.changesLocal, isFalse);
      expect(r.changesRemote, isTrue);
    });

    test('chỉ máy chủ sửa → lấy bản của máy chủ, cần lưu cục bộ', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final edited = x.edit(clock: b, title: 'x-từ-B');
      final r = mergeVaults(local: base, remote: vault([edited]), base: base);
      expect(r.merged.items.single.title, 'x-từ-B');
      expect(r.conflicts, isEmpty);
      expect(r.changesLocal, isTrue);
      expect(r.changesRemote, isFalse);
    });

    test('máy chủ sửa NHIỀU lần liên tiếp, máy này không đổi → KHÔNG báo xung đột (lỗi của cách parentHlc)', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      var v = x;
      for (var i = 1; i <= 5; i++) {
        v = v.edit(clock: b, title: 'lần $i');
      }
      final r = mergeVaults(local: base, remote: vault([v]), base: base);
      expect(r.conflicts, isEmpty);
      expect(r.merged.items.single.title, 'lần 5');
    });

    test('cả hai sửa cùng một mục → ghi nhận xung đột, bản HLC lớn hơn thắng', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final fromA = x.edit(clock: a, title: 'sửa ở A');
      final fromB = x.edit(clock: b, title: 'sửa ở B'); // sau, nên HLC lớn hơn
      final r = mergeVaults(local: vault([fromA]), remote: vault([fromB]), base: base);
      expect(r.conflicts.length, 1);
      expect(r.conflicts.single.local.title, 'sửa ở A');
      expect(r.conflicts.single.remote.title, 'sửa ở B');
      expect(r.merged.items.single.title, 'sửa ở B');
      expect(r.conflicts.single.winner.title, 'sửa ở B');
    });

    test('hai bên thêm mục khác nhau → hợp lại, không xung đột', () {
      final base = vault([]);
      final r = mergeVaults(local: vault([mk(a, 'từ A', rnd)]), remote: vault([mk(b, 'từ B', rnd)]), base: base);
      expect(r.merged.items.map((i) => i.title).toSet(), {'từ A', 'từ B'});
      expect(r.conflicts, isEmpty);
      expect(r.changesLocal && r.changesRemote, isTrue);
    });

    test('xóa vĩnh viễn ở một bên, bên kia không đụng → mục biến mất ở kết quả', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final purged = base.purge(x.id, clock: a);
      final r = mergeVaults(local: base, remote: purged, base: base);
      expect(r.merged.items, isEmpty);
      expect(r.merged.tombstones.single.id, x.id);
      expect(r.conflicts, isEmpty);
    });

    test('xóa vĩnh viễn rồi bên kia SỬA SAU → giữ bản sửa (HLC lớn hơn)', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final purged = base.purge(x.id, clock: a);
      final edited = x.edit(clock: b, title: 'sửa sau khi bị xóa');
      final r = mergeVaults(local: purged, remote: vault([edited]), base: base);
      expect(r.merged.items.single.title, 'sửa sau khi bị xóa');
      expect(r.merged.tombstones, isEmpty);
    });

    test('sửa rồi bên kia XÓA SAU → mục bị xóa (HLC của tombstone lớn hơn)', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final edited = x.edit(clock: a, title: 'sửa');
      final purged = base.purge(x.id, clock: b);
      final r = mergeVaults(local: vault([edited]), remote: purged, base: base);
      expect(r.merged.items, isEmpty);
      expect(r.merged.tombstones.single.id, x.id);
    });

    test('chuyển vào thùng rác ở một bên được lan sang bên kia (là một phiên bản bình thường)', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final trashed = x.moveToTrash(clock: b);
      final r = mergeVaults(local: base, remote: vault([trashed]), base: base);
      expect(r.merged.items.single.inTrash, isTrue);
    });

    test('chưa có bản chung (lần đồng bộ đầu): bên thiếu lấy từ bên có; cùng mục khác nhau → bản mới thắng + báo xung đột', () {
      final onlyLocal = mk(a, 'chỉ ở máy này', rnd);
      final onlyRemote = mk(b, 'chỉ ở máy chủ', rnd);
      final shared = mk(a, 'chung', rnd);
      final sharedEdited = shared.edit(clock: b, title: 'chung (đã sửa)');
      final r = mergeVaults(
        local: vault([onlyLocal, shared]),
        remote: vault([onlyRemote, sharedEdited]),
      );
      expect(r.merged.items.length, 3);
      expect(r.conflicts.length, 1);
      expect(r.merged.byId(shared.id)!.title, 'chung (đã sửa)');
    });

    test('nhóm: hợp hai bên, không trùng', () {
      final r = mergeVaults(
        local: const VaultData(groups: ['Dev', 'Cá nhân']),
        remote: const VaultData(groups: ['Cá nhân', 'Crypto']),
      );
      expect(r.merged.groups.toSet(), {'Dev', 'Cá nhân', 'Crypto'});
      expect(r.merged.groups.length, 3);
    });

    test('lũy đẳng: gộp kết quả với chính nó không đổi', () {
      final x = mk(a, 'x', rnd);
      final y = mk(b, 'y', rnd);
      final base = vault([x]);
      final r1 = mergeVaults(local: vault([x.edit(clock: a, title: 'x2')]), remote: vault([x, y]), base: base);
      final r2 = mergeVaults(local: r1.merged, remote: r1.merged, base: r1.merged);
      expect(sig(r2.merged), sig(r1.merged));
      expect(r2.conflicts, isEmpty);
      expect(r2.changesLocal || r2.changesRemote, isFalse);
    });
  });

  group('giải quyết xung đột', () {
    test('giữ bản của mình: nội dung của mình nhưng HLC mới lớn hơn cả hai', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final fromA = x.edit(clock: a, title: 'A');
      final fromB = x.edit(clock: b, title: 'B');
      final c = mergeVaults(local: vault([fromA]), remote: vault([fromB]), base: base).conflicts.single;
      final resolved = resolveConflict(c, ConflictChoice.keepLocal, clock: a);
      expect(resolved.title, 'A');
      expect(resolved.version > fromA.version && resolved.version > fromB.version, isTrue);
      // Lần đồng bộ sau: bản đã giải quyết thắng ở cả hai phía, hết xung đột.
      final again = mergeVaults(local: vault([resolved]), remote: vault([fromB]), base: base);
      expect(again.merged.items.single.title, 'A');
    });

    test('giữ bản của máy chủ', () {
      final x = mk(a, 'x', rnd);
      final base = vault([x]);
      final fromA = x.edit(clock: a, title: 'A');
      final fromB = x.edit(clock: b, title: 'B');
      final c = mergeVaults(local: vault([fromA]), remote: vault([fromB]), base: base).conflicts.single;
      expect(resolveConflict(c, ConflictChoice.keepRemote, clock: a).title, 'B');
    });
  });

  group('thử ngẫu nhiên (property test)', () {
    /// Dựng một kịch bản: kho gốc, hai bản sao A và B, mỗi bản được áp dụng các thao tác ngẫu nhiên xen kẽ nhau.
    (VaultData base, VaultData a, VaultData b) scenario(int seed) {
      _world = 1000;
      final r = Random(seed);
      final z = device('Z');
      final ca = device('A');
      final cb = device('B');
      final sr = SeededRandom(seed);

      var base = const VaultData();
      for (var i = 0, n = r.nextInt(7); i < n; i++) {
        base = base.upsert(mk(z, 'g$i', sr, group: r.nextBool() ? 'Dev' : ''));
      }
      var va = base;
      var vb = base;

      VaultData act(VaultData v, HlcClock clock) {
        final live = v.items.toList();
        switch (r.nextInt(6)) {
          case 0 when live.isNotEmpty:
            final it = live[r.nextInt(live.length)];
            return v.upsert(it.edit(clock: clock, title: '${it.title}*'));
          case 1 when live.isNotEmpty:
            final it = live[r.nextInt(live.length)];
            return v.upsert(it.moveToTrash(clock: clock));
          case 2 when live.isNotEmpty:
            final it = live[r.nextInt(live.length)];
            return it.inTrash ? v.upsert(it.restore(clock: clock)) : v;
          case 3 when live.isNotEmpty:
            return v.purge(live[r.nextInt(live.length)].id, clock: clock);
          default:
            return v.upsert(mk(clock, 'mới${r.nextInt(1000)}', sr, group: r.nextBool() ? 'Crypto' : ''));
        }
      }

      for (var step = 0, n = r.nextInt(10); step < n; step++) {
        if (r.nextBool()) {
          va = act(va, ca);
        } else {
          vb = act(vb, cb);
        }
      }
      return (base, va, vb);
    }

    test('giao hoán: gộp (A,B) và gộp (B,A) cho cùng kết quả và cùng tập xung đột (500 kịch bản)', () {
      for (var seed = 0; seed < 500; seed++) {
        final (base, va, vb) = scenario(seed);
        final r1 = mergeVaults(local: va, remote: vb, base: base);
        final r2 = mergeVaults(local: vb, remote: va, base: base);
        expect(sig(r1.merged), sig(r2.merged), reason: 'seed $seed');
        expect(conflictIds(r1), conflictIds(r2), reason: 'seed $seed');
        expect(r1.merged.groups.toSet(), r2.merged.groups.toSet(), reason: 'seed $seed');
      }
    });

    test('hội tụ: gộp tiếp kết quả với từng bên không làm đổi kết quả (500 kịch bản)', () {
      for (var seed = 0; seed < 500; seed++) {
        final (base, va, vb) = scenario(seed);
        final m = mergeVaults(local: va, remote: vb, base: base).merged;
        expect(sig(mergeVaults(local: m, remote: va, base: base).merged), sig(m), reason: 'seed $seed (với A)');
        expect(sig(mergeVaults(local: m, remote: vb, base: base).merged), sig(m), reason: 'seed $seed (với B)');
      }
    });

    test('không mất mục: mọi mục còn sống ở A hoặc B (và không bị tombstone mới hơn) vẫn có trong kết quả', () {
      for (var seed = 0; seed < 500; seed++) {
        final (base, va, vb) = scenario(seed);
        final m = mergeVaults(local: va, remote: vb, base: base).merged;
        final ids = {for (final i in m.items) i.id};
        final tombs = {for (final t in m.tombstones) t.id: t.version};
        for (final side in [va, vb]) {
          for (final i in side.items) {
            final inMerged = ids.contains(i.id);
            final tomb = tombs[i.id];
            // Mục không có trong kết quả thì phải do một tombstone có HLC lớn hơn.
            if (!inMerged) {
              expect(tomb != null && tomb > i.version, isTrue, reason: 'seed $seed: mất mục ${i.id} không có lý do');
            }
          }
        }
      }
    });
  });
}
