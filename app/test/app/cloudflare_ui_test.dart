import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/cloudflare_screens.dart';
import 'package:vankey/app/vault_controller.dart';

void main() {
  group('địa chỉ máy chủ', () {
    test('chỉ chấp nhận https, trừ máy cục bộ', () {
      expect(VaultController.isAllowedServerUrl('https://vankey.abc.workers.dev'), isTrue);
      expect(VaultController.isAllowedServerUrl('  https://vankey.abc.workers.dev/ '), isTrue);
      expect(VaultController.isAllowedServerUrl('http://127.0.0.1:8787'), isTrue);
      expect(VaultController.isAllowedServerUrl('http://localhost:8787'), isTrue);
      expect(VaultController.isAllowedServerUrl('http://10.0.2.2:8787'), isTrue);
    });

    test('từ chối http ra Internet, địa chỉ thiếu phần máy chủ, và chuỗi rác', () {
      expect(VaultController.isAllowedServerUrl('http://vankey.abc.workers.dev'), isFalse);
      expect(VaultController.isAllowedServerUrl('http://192.168.1.5:8787'), isFalse);
      expect(VaultController.isAllowedServerUrl('https://'), isFalse);
      expect(VaultController.isAllowedServerUrl('ftp://x.y'), isFalse);
      expect(VaultController.isAllowedServerUrl('vankey.workers.dev'), isFalse);
      expect(VaultController.isAllowedServerUrl(''), isFalse);
    });
  });

  testWidgets('màn đăng nhập: nút chỉ bật khi địa chỉ, tên đăng nhập và mật khẩu hợp lệ', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VaultController()..debugUnlock();
    await tester.pumpWidget(MaterialApp(home: CloudflareLoginScreen(controller: c)));

    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'http://vankey.example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'a.b');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu tài khoản'), 'matkhau-dai');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'http ra Internet không được phép');

    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'https://vankey.example.com');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu tài khoản'), '');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'đăng nhập cần có mật khẩu');

    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu tài khoản'), 'matkhau-dai');
    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'a');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'tên đăng nhập quá ngắn');
  });

  testWidgets('chế độ máy mới đòi thêm mật khẩu hoặc mã khôi phục của kho', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VaultController()..debugUnlock();
    await tester.pumpWidget(MaterialApp(home: CloudflareLoginScreen(controller: c, join: true)));

    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'https://vankey.example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'a.b');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu tài khoản'), 'matkhau-dai');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull, reason: 'thiếu mật khẩu kho');

    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu của kho'), 'mat-khau-kho');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);

    await tester.tap(find.text('Dùng mã khôi phục'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Mã khôi phục của kho'), findsOneWidget);
  });

  testWidgets('tạo tài khoản mới đòi mật khẩu từ 8 ký tự; đăng nhập thường chỉ cần có mật khẩu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VaultController()..debugUnlock();
    await tester.pumpWidget(MaterialApp(home: CloudflareLoginScreen(controller: c)));
    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'a.b');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu tài khoản'), 'ngan');
    await tester.pump();

    bool enabled() => tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;
    expect(enabled(), isTrue, reason: 'đăng nhập thường chỉ cần có mật khẩu');

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(enabled(), isFalse, reason: 'tạo tài khoản đòi mật khẩu dài');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu tài khoản (từ 8 ký tự)'), 'mat-khau-du-dai-1');
    await tester.pump();
    expect(enabled(), isTrue);
  });
}
