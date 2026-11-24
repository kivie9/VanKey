import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/search.dart';

import '../../helpers/helpers.dart';

void main() {
  var t = 1;
  final clock = HlcClock(node: 'A', nowMs: () => t++);

  Item item(String title, {ItemType type = ItemType.login, Map<String, String> values = const {}, String group = ''}) =>
      Item.create(type: type, title: title, clock: clock, values: values, group: group, random: SeededRandom(title.hashCode));

  group('foldVietnamese', () {
    test('bỏ dấu và đ, về chữ thường', () {
      expect(foldVietnamese('Ngân Hàng Á Châu'), 'ngan hang a chau');
      expect(foldVietnamese('Đường Nguyễn Huệ'), 'duong nguyen hue');
      expect(foldVietnamese('ỆỆ'), 'ee');
    });

    test('dạng tổ hợp và dạng dựng sẵn cho cùng kết quả', () {
      expect(foldVietnamese('Việt'), foldVietnamese('Việt'));
    });
  });

  group('matchesQuery', () {
    final bank = item('Ngân hàng Vietcombank', values: {'username': 'nguyen.van', 'password': 'BíMật123'}, group: 'Tài chính');

    test('tìm không dấu và không phân biệt hoa thường', () {
      expect(matchesQuery(bank, 'ngan hang'), isTrue);
      expect(matchesQuery(bank, 'VIETCOMBANK'), isTrue);
      expect(matchesQuery(bank, 'tai chinh'), isTrue, reason: 'tìm theo thẻ');
      expect(matchesQuery(bank, 'nguyen.van'), isTrue, reason: 'tìm theo tên đăng nhập (không bí mật)');
    });

    test('nhiều từ: thứ tự bất kỳ, thiếu một từ là không khớp', () {
      expect(matchesQuery(bank, 'vietcombank ngan'), isTrue);
      expect(matchesQuery(bank, 'ngan techcombank'), isFalse);
    });

    test('KHÔNG tìm trong trường bí mật (mật khẩu, số thẻ, cụm từ khôi phục)', () {
      expect(matchesQuery(bank, 'BíMật123'), isFalse);
      expect(matchesQuery(bank, 'bimat'), isFalse);
      final wallet = item('Ví', type: ItemType.crypto, values: {'wallet': 'Ledger', 'seedPhrase': 'tower anchor velvet'});
      expect(matchesQuery(wallet, 'tower'), isFalse);
      expect(matchesQuery(wallet, 'ledger'), isTrue);
      final card = item('Visa', type: ItemType.card, values: {'holder': 'NGUYEN', 'number': '4111 1111 1111 1111'});
      expect(matchesQuery(card, '4111'), isFalse);
    });

    test('truy vấn rỗng hoặc chỉ khoảng trắng khớp mọi mục; tìm theo loại', () {
      expect(matchesQuery(bank, ''), isTrue);
      expect(matchesQuery(bank, '   '), isTrue);
      expect(matchesQuery(item('Thẻ', type: ItemType.card, values: {'holder': 'A'}), 'card'), isTrue);
    });
  });
}
