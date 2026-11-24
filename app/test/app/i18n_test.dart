import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/i18n.dart';
import 'package:vankey/app/i18n_en.dart';

Set<String> _placeholders(String s) => RegExp(r'\{p\d+\}').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  tearDown(() => Lang.set('vi'));

  test('mọi bản dịch giữ đúng các chỗ chèn {p0}, {p1}', () {
    for (final e in enStrings.entries) {
      expect(_placeholders(e.value), _placeholders(e.key), reason: 'lệch chỗ chèn: "${e.key}"');
    }
  });

  test('không có bản dịch rỗng', () {
    for (final e in enStrings.entries) {
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
  });

  test('tiếng Việt giữ nguyên, tiếng Anh dịch, thiếu bản dịch thì dùng tiếng Việt', () {
    Lang.set('vi');
    expect(tr('Hủy'), 'Hủy');
    Lang.set('en');
    expect(tr('Hủy'), 'Cancel');
    expect(tr('Chuỗi chưa có bản dịch'), 'Chuỗi chưa có bản dịch');
  });

  test('chèn giá trị vào chuỗi', () {
    Lang.set('en');
    expect(tr('Đã nhập {p0} mục', {'p0': 3}), 'Imported 3 items');
    Lang.set('vi');
    expect(tr('Đã nhập {p0} mục', {'p0': 3}), 'Đã nhập 3 mục');
  });

  test('Lang.resolve: theo hệ thống chỉ chọn tiếng Anh khi máy dùng tiếng Anh', () {
    expect(Lang.resolve('system', 'en'), 'en');
    expect(Lang.resolve('system', 'fr'), 'vi');
    expect(Lang.resolve('vi', 'en'), 'vi');
    expect(Lang.resolve('en', 'vi'), 'en');
  });
}
