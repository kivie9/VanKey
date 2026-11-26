// Xóa dữ liệu mẫu: chỉ xóa mục mẫu còn nguyên, giữ mục của người dùng và mục mẫu đã bị sửa.
import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

void main() {
  test('xóa dữ liệu mẫu chỉ xóa mục mẫu còn nguyên', () {
    final c = VaultController()..debugUnlock();
    addTearDown(c.dispose);
    c.upsert(Item.create(type: ItemType.login, title: 'Ngân hàng của tôi', clock: c.clock, values: {'username': 'toi'}));
    final added = c.addDemoData();
    expect(c.demoItems, hasLength(added));

    // Người dùng sửa một mục mẫu: coi là của họ, không xóa.
    final github = c.data.items.firstWhere((i) => i.title == 'GitHub');
    c.upsert(github.copyWith(title: 'GitHub công ty'));

    expect(c.removeDemoData(), added - 1);
    final titles = c.data.items.map((i) => i.title).toList();
    expect(titles, containsAll(['Ngân hàng của tôi', 'GitHub công ty']));
    expect(titles, hasLength(2));
    expect(c.demoItems, isEmpty);
    expect(c.removeDemoData(), 0);
  });

  test('nhận ra cả mục mẫu đã nạp từ ngày khác (trường hạn dùng khác)', () {
    final c = VaultController()..debugUnlock();
    addTearDown(c.dispose);
    final n = c.addDemoData();
    final key = c.data.items.firstWhere((i) => i.title == 'OpenAI API key');
    c.upsert(key.copyWith(fields: [for (final f in key.fields) f.key == 'expiry' ? f.copyWith(value: '2020-01-01') : f]));
    expect(c.removeDemoData(), n);
  });
}
