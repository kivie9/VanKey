import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vankey/app/qr_image.dart';
import 'package:vankey/core/totp/migration.dart';
import 'package:vankey/core/totp/otpauth.dart';

void main() {
  test('đọc lại đúng link otpauth từ ảnh QR', () {
    const link = 'otpauth://totp/GitHub:van?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
    expect(QrImageDecoder.decode(QrImageDecoder.encodePng(link)), link);
  });

  test('đọc được mã migration của Google Authenticator (nhiều tài khoản) từ ảnh', () {
    final uri = Migration.encodeUri(const [
      OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'A', account: 'a@x.com'),
      OtpAuth(type: OtpType.totp, secret: 'GEZDGNBVGY3TQOJQ', issuer: 'B', account: 'b@x.com'),
    ]);
    final back = QrImageDecoder.decode(QrImageDecoder.encodePng(uri, scale: 4));
    expect(back, uri);
    expect(Migration.parseUri(back!).entries.map((e) => e.issuer), ['A', 'B']);
  });

  test('ảnh chụp màn hình rất lớn (QR nhỏ trên nền rộng) vẫn đọc được', () {
    const link = 'otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X';
    final qr = img.decodePng(QrImageDecoder.encodePng(link, scale: 5))!;
    final canvas = img.Image(width: 2400, height: 1400);
    img.fill(canvas, color: img.ColorRgb8(240, 240, 240));
    img.compositeImage(canvas, qr, dstX: 900, dstY: 400);
    final png = Uint8List.fromList(img.encodePng(canvas));
    expect(QrImageDecoder.decode(png), link);
  });

  test('ảnh không có mã QR hoặc byte rác trả về null, không ném lỗi', () {
    final blank = img.Image(width: 300, height: 300);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(QrImageDecoder.decode(Uint8List.fromList(img.encodePng(blank))), isNull);
    expect(QrImageDecoder.decode(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    expect(QrImageDecoder.decode(Uint8List(0)), isNull);
  });
}
