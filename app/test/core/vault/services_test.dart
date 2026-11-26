import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/services.dart';

final _clock = HlcClock(node: 'test');

Item _item(String title, {String url = '', ItemType type = ItemType.login}) =>
    Item.create(type: type, title: title, clock: _clock, values: {if (url.isNotEmpty) 'url': url, 'username': 'u'});

String? _key(String title, {String url = '', ItemType type = ItemType.login}) => serviceOf(_item(title, url: url, type: type))?.key;

void main() {
  test('địa chỉ web quyết định dịch vụ, tên đặt tùy ý vẫn đúng nhóm', () {
    expect(_key('FB bán hàng', url: 'https://www.facebook.com/login'), 's:facebook');
    expect(_key('Cá nhân', url: 'fb.com'), 's:facebook');
    expect(_key('Mail phụ', url: 'mail.google.com'), 's:google');
    expect(_key('x', url: 'HTTPS://Accounts.Google.COM./'), 's:google');
    expect(_key('Server', url: 'https://signin.aws.amazon.com/console'), 's:aws');
    expect(_key('Mua sắm', url: 'amazon.com'), 's:amazon');
  });

  test('địa chỉ giả mạo không được xếp vào dịch vụ thật', () {
    expect(_key('Facebook', url: 'https://facebook.com.trang-la.ru/login'), 'd:trang-la.ru');
    expect(_key('Facebook', url: 'https://facebook.com@evil.com/'), 'd:evil.com');
    expect(_key('Facebook', url: 'https://notfacebook.com'), 'd:notfacebook.com');
    expect(_key('Facebook', url: 'https://evil.com/facebook.com'), 'd:evil.com');
    expect(_key('Google', url: 'google.com.vn.evil.com'), 'd:evil.com');
  });

  test('tên miền chính: đuôi hai tầng và đuôi dùng chung không gom lẫn', () {
    expect(baseDomain('login.congty.com.vn'), 'congty.com.vn');
    expect(baseDomain('a.b.example.org'), 'example.org');
    expect(baseDomain('an.github.io'), 'an.github.io');
    expect(baseDomain('binh.github.io'), 'binh.github.io');
    expect(baseDomain('192.168.1.1'), '192.168.1.1');
  });

  test('không có địa chỉ web thì gom theo cả tên, bỏ qua hoa thường, dấu, khoảng trắng', () {
    expect(_key('  facebook '), 's:facebook');
    expect(_key('Gmail'), 's:google');
    expect(_key('Ngân  Hàng ABC'), _key('ngan hang abc'));
    expect(_key('Facebok'), 't:facebok');
    expect(_key('FB bán hàng'), 't:fb ban hang');
  });

  test('chuỗi không phải địa chỉ web bị bỏ qua', () {
    expect(hostOf('Facebook'), isNull);
    expect(hostOf('android://abc@com.facebook.katana/'), isNull);
    expect(hostOf('trang web của tôi'), isNull);
    expect(hostOf('http://localhost:8080/x'), 'localhost');
  });

  test('thẻ, Wi-Fi, ghi chú không bị xếp chồng chỉ vì trùng tên', () {
    expect(_key('Nhà', type: ItemType.wifi), isNull);
    final stacks = stackByService([_item('Nhà', type: ItemType.wifi), _item('Nhà', type: ItemType.wifi)], byName: true);
    expect(stacks.length, 2);
  });

  test('xếp chồng: từ hai tài khoản trở lên mới thành nhóm', () {
    final stacks = stackByService([
      _item('FB bán hàng', url: 'facebook.com'),
      _item('Facebook'),
      _item('Netflix', url: 'netflix.com'),
    ], byName: true);
    expect(stacks.map((s) => (s.name, s.items.length, s.isStack)), [('Facebook', 2, true), ('Netflix', 1, false)]);
  });

  test('gợi ý cho mục cũ: lỗi gõ và tên có chứa dịch vụ; không đoán khi mơ hồ', () {
    String? s(String title, {String url = '', ItemType type = ItemType.login}) => suggestService(_item(title, url: url, type: type))?.id;
    expect(s('Facebok'), 'facebook');
    expect(s('Faecbook'), 'facebook');
    expect(s('Gooogle'), 'google');
    expect(s('FB bán hàng'), 'facebook');
    expect(s('Netflix gia đình'), 'netflix');
    expect(s('Facebook'), isNull, reason: 'đã đúng tên');
    expect(s('FB bán hàng', url: 'example.com'), isNull, reason: 'đã có địa chỉ');
    expect(s('Google và Facebook'), isNull, reason: 'hai dịch vụ');
    expect(s('Ngân hàng'), isNull);
    expect(s('x'), isNull);
    expect(s('FB', type: ItemType.note), isNull);
  });

  test('bảng dịch vụ không trùng tên miền hay mã', () {
    final domains = [for (final s in knownServices) ...s.domains];
    expect(domains.toSet().length, domains.length);
    expect(knownServices.map((s) => s.id).toSet().length, knownServices.length);
  });
}
