import '../core/vault/hlc.dart';
import '../core/vault/models.dart';

/// Dữ liệu mẫu để xem giao diện: đủ loại mục, logo, 2FA các kiểu, nhắc nhở, thẻ, yêu thích, thùng rác...
/// Tất cả đều là giá trị giả, không phải tài khoản thật.
List<Item> buildDemoItems(HlcClock clock, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  const secret = 'JBSWY3DPEHPK3PXP';
  Item mk(
    ItemType type,
    String title, {
    Map<String, String> v = const {},
    String tag = '',
    bool fav = false,
    TotpParams? totp,
    List<Field> extra = const [],
    Reminder? reminder,
    bool trash = false,
  }) {
    var i = Item.create(type: type, title: title, clock: clock, values: v, totp: totp, group: tag, favorite: fav, customFields: extra);
    if (reminder != null) i = i.copyWith(reminder: reminder);
    if (trash) i = i.moveToTrash(clock: clock);
    return i;
  }

  String month(int ahead) {
    final d = DateTime(t.year, t.month + ahead);
    return '${d.month.toString().padLeft(2, '0')}/${d.year % 100}';
  }

  return [
    // Tài khoản có logo thương hiệu
    mk(ItemType.login, 'Facebook', v: {'username': 'van.demo@mail.com', 'password': 'Fb#2024-demo', 'url': 'facebook.com'}, tag: 'Cá nhân', fav: true, totp: const TotpParams(secret: secret)),
    mk(ItemType.login, 'Google', v: {'username': 'van.demo@gmail.com', 'password': 'G00gle!demoPass', 'url': 'accounts.google.com'}, tag: 'Cá nhân', totp: const TotpParams(secret: secret)),
    mk(ItemType.login, 'Gmail công việc', v: {'username': 'van@congty.vn', 'password': 'Cong-ty_2024!x', 'url': 'mail.google.com'}, tag: 'Công việc'),
    mk(ItemType.login, 'GitHub', v: {'username': 'van-dev', 'password': 'gh-Demo-Secret-9921', 'url': 'github.com'}, tag: 'Công việc', fav: true, totp: const TotpParams(secret: secret, digits: 6)),
    mk(ItemType.login, 'Meta Business', v: {'username': 'ads@congty.vn', 'password': 'MetaB1z#demo', 'url': 'business.facebook.com'}, tag: 'Công việc'),
    mk(ItemType.login, 'Netflix', v: {'username': 'gia.dinh@mail.com', 'password': 'netflix-123456', 'url': 'netflix.com'}, tag: 'Giải trí'),
    mk(ItemType.login, 'Spotify', v: {'username': 'van.music', 'password': 'Sp0tify!Demo', 'url': 'spotify.com'}, tag: 'Giải trí'),
    mk(ItemType.login, 'Discord', v: {'username': 'van#1234', 'password': 'Disc0rd-demo-77', 'url': 'discord.com'}, tag: 'Giải trí', totp: const TotpParams(secret: secret)),
    mk(ItemType.login, 'Apple ID', v: {'username': 'van.demo@icloud.com', 'password': 'Appl3-Id-Demo!', 'url': 'appleid.apple.com'}, tag: 'Cá nhân'),
    // Không nhận ra thương hiệu: chữ cái đầu
    mk(ItemType.login, 'Cổng thông tin công ty', v: {'username': 'nv0123', 'password': 'matkhau-yeu', 'url': 'portal.congty.vn'}, tag: 'Công việc'),
    mk(ItemType.login, 'Diễn đàn xe máy', v: {'username': 'bikerVN', 'password': 'matkhau-yeu'}), // trùng mật khẩu, không thẻ, không link
    mk(ItemType.login, 'Tài khoản có tên rất rất dài để thử việc cắt chữ trên một dòng của danh sách', v: {'username': 'tai-khoan-co-ten-dang-nhap-cung-rat-dai@vi-du-ten-mien-dai.example.com', 'password': 'x'}),
    // Nhắc đổi mật khẩu: quá hạn và sắp đến hạn
    mk(ItemType.login, 'Ngân hàng online (quá hạn đổi MK)', v: {'username': '0901234567', 'password': 'Bank!Old-2022'}, tag: 'Tài chính', reminder: Reminder(months: 3, noticeDays: 7, lastChangedAt: t.subtract(const Duration(days: 150)))),
    mk(ItemType.login, 'Ví điện tử (sắp đến hạn)', v: {'username': '0907654321', 'password': 'Vi#Dien-Tu-55'}, tag: 'Tài chính', reminder: Reminder(months: 3, noticeDays: 14, lastChangedAt: t.subtract(const Duration(days: 80)))),
    // 2FA độc lập
    mk(ItemType.totp, 'Amazon AWS', v: {'account': 'root@congty.vn', 'service': 'AWS'}, tag: 'Công việc', totp: const TotpParams(secret: secret)),
    mk(ItemType.totp, 'Cloudflare (8 số, SHA-256)', v: {'account': 'van@congty.vn'}, tag: 'Công việc', totp: const TotpParams(secret: secret, digits: 8, algorithm: TotpAlgorithm.sha256)),
    mk(ItemType.totp, 'Token ngân hàng (HOTP)', v: {'account': 'Token cứng'}, tag: 'Tài chính', totp: const TotpParams(secret: secret, kind: 'hotp', counter: 7)),
    mk(ItemType.totp, 'Steam', v: {'account': 'van_gamer'}, tag: 'Giải trí', totp: const TotpParams(secret: secret, kind: 'steam', digits: 5)),
    mk(ItemType.totp, 'Dịch vụ chu kỳ 60 giây', v: {'account': 'demo'}, totp: const TotpParams(secret: secret, period: 60)),
    // Khóa / API
    mk(ItemType.key, 'OpenAI API key', v: {'service': 'OpenAI', 'key': 'sk-demo-0000000000000000000000000000', 'expiry': '${t.year + 1}-01-15'}, tag: 'Công việc'),
    mk(ItemType.key, 'Khóa SSH máy chủ (sắp hết hạn)', v: {'service': 'VPS', 'key': 'ssh-ed25519 AAAADEMO van@laptop', 'expiry': '${t.add(const Duration(days: 12)).year}-${t.add(const Duration(days: 12)).month.toString().padLeft(2, '0')}-${t.add(const Duration(days: 12)).day.toString().padLeft(2, '0')}'}, tag: 'Công việc'),
    // Ví tiền mã hóa
    mk(ItemType.crypto, 'Ví Metamask', v: {'wallet': 'MetaMask', 'address': '0xDEMO0000000000000000000000000000000000AB', 'seedPhrase': 'apple banana cherry delta eagle frost grape hotel igloo jungle kite lemon'}, tag: 'Tài chính'),
    // Thẻ ngân hàng
    mk(ItemType.card, 'Visa Techcombank', v: {'holder': 'NGUYEN VAN A', 'number': '4111111111111111', 'expiry': month(18), 'cvv': '123', 'pin': '1234'}, tag: 'Tài chính', fav: true),
    mk(ItemType.card, 'Mastercard (sắp hết hạn)', v: {'holder': 'NGUYEN VAN A', 'number': '5555555555554444', 'expiry': month(1), 'cvv': '456'}, tag: 'Tài chính'),
    mk(ItemType.card, 'Thẻ cũ (đã hết hạn)', v: {'holder': 'NGUYEN VAN A', 'number': '4000056655665556', 'expiry': month(-3), 'cvv': '789'}, tag: 'Tài chính'),
    // Wi-Fi
    mk(ItemType.wifi, 'Wi-Fi nhà', v: {'ssid': 'NhaVan_5G', 'password': 'wifi-nha-2024', 'security': 'WPA2'}, tag: 'Cá nhân'),
    mk(ItemType.wifi, 'Wi-Fi văn phòng', v: {'ssid': 'CongTy-Guest', 'password': 'khach-2024', 'security': 'WPA3'}, tag: 'Công việc'),
    // Ghi chú
    mk(ItemType.note, 'Ghi chú ngắn', v: {'content': 'Mã tủ gửi đồ: 4821'}),
    mk(ItemType.note, 'Hướng dẫn khôi phục server', v: {'content': 'Bước 1: đăng nhập VPS\nBước 2: chạy lệnh khôi phục\nBước 3: kiểm tra log\n\n(Nội dung nhiều dòng để thử hiển thị.)'}, tag: 'Công việc', fav: true),
    // Mục đăng nhập có trường tùy ý và ghi chú riêng tư
    mk(ItemType.login, 'Hosting có trường tùy ý', v: {'username': 'admin', 'password': 'Host!ing-demo-31', 'url': 'host.example.com'}, tag: 'Công việc', extra: const [
      Field(key: null, label: 'Mã khách hàng', value: 'KH-00123'),
      Field(key: null, label: 'Câu hỏi bảo mật', value: 'Tên con vật đầu tiên?', secret: true),
      Field(key: 'notes', value: 'Hỗ trợ: gọi 1900-xxxx, báo mã khách hàng.', secret: true, kind: 'multiline'),
    ]),
    // Đã vào thùng rác
    mk(ItemType.login, 'Tài khoản cũ (trong thùng rác)', v: {'username': 'cu', 'password': 'cu-123'}, trash: true),
  ];
}
