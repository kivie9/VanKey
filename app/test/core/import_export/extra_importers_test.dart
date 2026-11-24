import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/import_export/extra_importers.dart';
import 'package:vankey/core/import_export/imported_item.dart';
import 'package:vankey/core/import_export/importers.dart';
import 'package:vankey/core/vault/models.dart';

const _keepass = '''<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<KeePassFile>
  <Meta><DatabaseName>Test</DatabaseName></Meta>
  <Root>
    <Group>
      <Name>Database</Name>
      <Entry>
        <String><Key>Title</Key><Value>Gốc</Value></String>
        <String><Key>UserName</Key><Value>root-user</Value></String>
        <String><Key>Password</Key><Value>p1</Value></String>
      </Entry>
      <Group>
        <Name>Công việc</Name>
        <Entry>
          <String><Key>Title</Key><Value>GitHub</Value></String>
          <String><Key>UserName</Key><Value>van</Value></String>
          <String><Key>Password</Key><Value>secret-1</Value></String>
          <String><Key>URL</Key><Value>https://github.com</Value></String>
          <String><Key>Notes</Key><Value>ghi chú</Value></String>
          <String><Key>otp</Key><Value>otpauth://totp/GitHub:van?secret=JBSWY3DPEHPK3PXP&amp;issuer=GitHub</Value></String>
        </Entry>
        <Group>
          <Name>Ngân hàng</Name>
          <Entry>
            <String><Key>Title</Key><Value>Vietcombank</Value></String>
            <String><Key>UserName</Key><Value>acc</Value></String>
          </Entry>
        </Group>
      </Group>
      <Group>
        <Name>Recycle Bin</Name>
        <Entry>
          <String><Key>Title</Key><Value>Đã xóa</Value></String>
          <String><Key>Password</Key><Value>x</Value></String>
        </Entry>
      </Group>
    </Group>
  </Root>
</KeePassFile>''';

Uint8List _onePux(Map<String, dynamic> data) {
  final bytes = utf8.encode(jsonEncode(data));
  final archive = Archive()
    ..addFile(ArchiveFile('export.attributes', 2, utf8.encode('{}')))
    ..addFile(ArchiveFile('export.data', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('KeePass XML', () {
    test('đọc mục, nhóm lồng nhau, bỏ thùng rác, nhận khóa 2FA', () {
      final r = Importers.auto(_keepass);
      final byTitle = {for (final i in r.items) i.title: i};
      expect(byTitle.keys, containsAll(['Gốc', 'GitHub', 'Vietcombank']));
      expect(byTitle.containsKey('Đã xóa'), isFalse);
      expect(byTitle['Gốc']!.group, '');
      expect(byTitle['GitHub']!.group, 'Công việc');
      expect(byTitle['Vietcombank']!.group, 'Công việc / Ngân hàng');
      expect(byTitle['GitHub']!.password, 'secret-1');
      expect(byTitle['GitHub']!.totp?.secret, 'JBSWY3DPEHPK3PXP');
      expect(byTitle['GitHub']!.notes, 'ghi chú');
    });

    test('XML hỏng ném lỗi rõ ràng, không crash', () {
      expect(() => ExtraImporters.keepassXml('<KeePassFile><Root>'), throwsA(anything));
    });
  });

  group('1Password .1pux', () {
    final data = {
      'accounts': [
        {
          'vaults': [
            {
              'attrs': {'name': 'Cá nhân'},
              'items': [
                {
                  'categoryUuid': '001',
                  'favIndex': 1,
                  'overview': {'title': 'Gmail', 'url': 'https://mail.google.com'},
                  'details': {
                    'loginFields': [
                      {'designation': 'username', 'value': 'a@gmail.com'},
                      {'designation': 'password', 'value': 'pw-123'},
                    ],
                    'sections': [
                      {
                        'fields': [
                          {'value': {'totp': 'JBSWY3DPEHPK3PXP'}},
                        ],
                      },
                    ],
                  },
                },
                {'categoryUuid': '003', 'overview': {'title': 'Ghi chú'}, 'details': {'notesPlain': 'nội dung'}},
                {'categoryUuid': '006', 'overview': {'title': 'Giấy tờ'}, 'details': <String, dynamic>{}},
              ],
            },
          ],
        },
      ],
    };

    test('đọc đăng nhập kèm 2FA, ghi chú; bỏ qua loại chưa hỗ trợ có cảnh báo', () {
      final r = Importers.autoBytes(_onePux(data));
      expect(r.items.map((i) => i.title), ['Gmail', 'Ghi chú']);
      final g = r.items.first;
      expect(g.username, 'a@gmail.com');
      expect(g.password, 'pw-123');
      expect(g.group, 'Cá nhân');
      expect(g.totp?.secret, 'JBSWY3DPEHPK3PXP');
      expect(r.items.last.type, ItemType.note);
      expect(r.warnings.map((w) => w.code), [ImportWarningCode.skippedUnsupported]);
    });

    test('file zip không có export.data bị từ chối', () {
      final archive = Archive()..addFile(ArchiveFile('khac.txt', 1, [65]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(() => ExtraImporters.onePux(bytes), throwsA(anything));
    });

    test('byte không phải zip vẫn đi đường văn bản', () {
      final r = Importers.autoBytes(Uint8List.fromList(utf8.encode('otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X')));
      expect(r.items, hasLength(1));
    });
  });
}
