import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/onboarding_screen.dart';
import 'package:vankey/app/vault_controller.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: VaultController(), serverOnly: false)));
}

bool _enabled(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

void main() {
  testWidgets('màn đầu có hai lựa chọn máy chủ và liên kết nhỏ chỉ dùng trên máy; không còn "Dùng ngay"', (tester) async {
    await _open(tester);
    expect(find.text('Dùng máy chủ VanKey'), findsOneWidget);
    expect(find.text('Tự dựng máy chủ (self-host)'), findsOneWidget);
    expect(find.textContaining('Chỉ dùng trên máy'), findsNothing);
    expect(find.textContaining('Dùng ngay'), findsNothing);
    expect(find.byType(TextField), findsNothing, reason: 'chưa phải nhập gì ở màn chọn');
  });

  testWidgets('máy chủ VanKey: đăng nhập bằng tên đăng nhập và mật khẩu, không có ô địa chỉ máy chủ', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Dùng máy chủ VanKey'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), findsNothing);
    expect(find.widgetWithText(TextField, 'Tên đăng nhập'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mật khẩu'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nhập lại mật khẩu'), findsNothing, reason: 'đăng nhập không cần nhập lại');
    expect(_enabled(tester), isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'nguoi.dung');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), 'bat-ky');
    await tester.pump();
    expect(_enabled(tester), isTrue, reason: 'đăng nhập chỉ cần có tên hợp lệ và mật khẩu');

    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'a b');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'tên đăng nhập sai quy tắc');
  });

  testWidgets('tạo tài khoản: mật khẩu từ 8 ký tự, nhập lại phải khớp, có ô mã mời tùy chọn', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Dùng máy chủ VanKey'));
    await tester.pump();
    await tester.tap(find.text('Tạo tài khoản').first);
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Nhập lại mật khẩu'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mã mời (nếu máy chủ yêu cầu)'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'nguoi.dung');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), 'ngan123');
    await tester.enterText(find.widgetWithText(TextField, 'Nhập lại mật khẩu'), 'ngan123');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'dưới 8 ký tự');
    expect(find.text('Cần ít nhất 8 ký tự'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), 'mat-khau-du-dai-1');
    await tester.enterText(find.widgetWithText(TextField, 'Nhập lại mật khẩu'), 'mat-khau-du-dai-2');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'nhập lại chưa khớp');
    expect(find.text('Chưa khớp'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Nhập lại mật khẩu'), 'mat-khau-du-dai-1');
    await tester.pump();
    expect(_enabled(tester), isTrue, reason: 'mã mời không bắt buộc');
  });

  testWidgets('tự dựng máy chủ: có thêm ô địa chỉ máy chủ và chỉ nhận https', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Tự dựng máy chủ (self-host)'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'nguoi.dung');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), 'bat-ky');
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'http://vankey.example.com');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'http ra Internet không được phép');

    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'https://vankey.example.com');
    await tester.pump();
    expect(_enabled(tester), isTrue);
  });

  testWidgets('màn đầu: có lựa chọn Google Drive khi bật; không có khi không hỗ trợ (iOS, máy tính)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: VaultController(), driveAvailable: true, serverOnly: false)));
    expect(find.text('Dùng Google Drive của bạn'), findsOneWidget);
    await tester.tap(find.text('Dùng Google Drive của bạn'));
    await tester.pump();
    expect(find.text('Đăng nhập Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'chưa đăng nhập thì chưa hỏi mật khẩu');

    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: VaultController(), driveAvailable: false, serverOnly: false)));
    await tester.pump();
    expect(find.text('Dùng Google Drive của bạn'), findsNothing);
  });

  testWidgets('bản MVP: mở thẳng đăng nhập máy chủ VanKey; không có màn chọn, self-host, Drive hay mã mời', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: VaultController(), driveAvailable: true, serverOnly: true)));

    expect(find.widgetWithText(TextField, 'Tên đăng nhập'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mật khẩu'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), findsNothing);
    expect(find.text('Quay lại'), findsNothing);
    expect(find.text('Tự dựng máy chủ (self-host)'), findsNothing);
    expect(find.text('Dùng Google Drive của bạn'), findsNothing);

    await tester.tap(find.text('Tạo tài khoản').first);
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Nhập lại mật khẩu'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mã mời (nếu máy chủ yêu cầu)'), findsNothing);
  });
}
