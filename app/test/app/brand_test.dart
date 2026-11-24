import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:vankey/app/brand.dart';
import 'package:vankey/app/widgets/common.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';

void main() {
  tearDown(() => BrandConfig.enabled = true);

  group('nhận diện thương hiệu', () {
    test('theo tên: Facebook, Gmail (là Google), GitHub, Spotify...', () {
      expect(brandFor('Facebook')?.icon, SimpleIcons.facebook);
      expect(brandFor('Gmail cá nhân')?.icon, SimpleIcons.gmail, reason: 'Gmail có biểu tượng riêng, không phải chữ G');
      expect(brandFor('Meta Business')?.icon, SimpleIcons.meta, reason: 'Meta không phải Facebook');
      expect(brandFor('Facebook')?.icon, SimpleIcons.facebook);
      expect(brandFor('Google')?.multicolor, isTrue);
      expect(brandFor('GitHub')?.icon, SimpleIcons.github);
      expect(brandFor('my-spotify')?.icon, SimpleIcons.spotify);
      expect(brandFor('Cloudflare Dashboard')?.icon, SimpleIcons.cloudflare);
      expect(brandFor('Tài khoản ZALO')?.icon, SimpleIcons.zalo);
    });

    test('theo địa chỉ web khi tên không rõ', () {
      expect(brandFor('Tài khoản công việc', 'https://accounts.google.com/signin')?.icon, SimpleIcons.google);
      expect(brandFor('Login', 'github.com')?.icon, SimpleIcons.github);
      expect(brandFor('Mạng xã hội', 'https://www.facebook.com/')?.icon, SimpleIcons.facebook);
    });

    test('không nhận nhầm: tên ngắn phải khớp nguyên từ', () {
      expect(brandFor('Xbox'), isNull, reason: '"x" chỉ khớp khi đứng riêng');
      expect(brandFor('Applebees'), isNull);
      expect(brandFor('Steamboat Bank'), isNull);
      expect(brandFor('Vietcombank'), isNull);
      expect(brandFor('Wi-Fi nhà'), isNull);
      expect(brandFor(''), isNull);
    });

    test('"X" đứng riêng và Twitter đều ra logo X', () {
      expect(brandFor('X')?.icon, SimpleIcons.x);
      expect(brandFor('Twitter')?.icon, SimpleIcons.x);
    });

    test('thương hiệu đã bị gỡ khỏi bộ biểu tượng thì không có logo (dùng chữ cái)', () {
      expect(brandFor('Microsoft'), isNull);
      expect(brandFor('Amazon'), isNull);
      expect(brandFor('LinkedIn'), isNull);
    });
  });

  group('Avatar', () {
    testWidgets('mục Facebook hiện logo, mục lạ hiện chữ cái đầu', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Column(children: [Avatar('Facebook'), Avatar('Vietcombank')])));
      expect(find.byIcon(SimpleIcons.facebook), findsOneWidget);
      expect(find.text('V'), findsOneWidget);
      expect(find.text('F'), findsNothing);
    });

    testWidgets('tắt logo trong cài đặt thì quay về chữ cái đầu', (tester) async {
      BrandConfig.enabled = false;
      await tester.pumpWidget(const MaterialApp(home: Avatar('Facebook')));
      expect(find.byIcon(SimpleIcons.facebook), findsNothing);
      expect(find.text('F'), findsOneWidget);
    });

    testWidgets('Avatar.forItem dùng cả địa chỉ web của mục', (tester) async {
      final item = Item.create(type: ItemType.login, title: 'Công việc', clock: HlcClock(node: 'test'), values: {'url': 'https://github.com/org'});
      await tester.pumpWidget(MaterialApp(home: Avatar.forItem(item)));
      expect(find.byIcon(SimpleIcons.github), findsOneWidget);
    });

    testWidgets('logo màu gần đen (GitHub) vẫn nhìn thấy được ở giao diện tối', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const Avatar('GitHub')));
      final box = tester.widget<Container>(find.byType(Container).first);
      final bg = (box.decoration! as BoxDecoration).color!;
      expect(bg.computeLuminance(), greaterThan(0.02), reason: 'nền không được gần như đen tuyền trên nền tối');
    });
  });
}
