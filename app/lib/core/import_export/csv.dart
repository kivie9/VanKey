import '../errors.dart';

/// Đọc CSV theo RFC 4180: ô có ngoặc kép, ngoặc kép lồng nhau (`""`), xuống dòng bên trong ô,
/// dòng kết thúc CRLF/LF/CR, và dấu BOM ở đầu file. Dòng trống bị bỏ.
List<List<String>> parseCsv(String input) {
  const maxChars = 16 * 1024 * 1024;
  if (input.length > maxChars) throw const InvalidInputException('file CSV quá lớn');
  final text = input.startsWith('﻿') ? input.substring(1) : input;

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var quoted = false; // ô hiện tại có bắt đầu bằng ngoặc kép

  void endField() {
    row.add(field.toString());
    field.clear();
    quoted = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty && !quoted) {
      inQuotes = true;
      quoted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endField();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (inQuotes) throw const InvalidInputException('CSV: dấu ngoặc kép chưa được đóng');
  if (field.isNotEmpty || row.isNotEmpty || quoted) {
    endField();
    rows.add(row);
  }
  return [
    for (final r in rows)
      if (!(r.length == 1 && r.first.isEmpty)) r,
  ];
}

String _csvField(String v) {
  final needsQuote = v.contains(RegExp(r'[",\r\n]')) || v.startsWith(' ') || v.endsWith(' ');
  return needsQuote ? '"${v.replaceAll('"', '""')}"' : v;
}

/// Ghi CSV (CRLF). Dữ liệu được giữ **nguyên văn**, không thêm ký tự chống công thức vì điều đó làm đổi mật khẩu.
String writeCsv(List<List<String>> rows) => '${rows.map((r) => r.map(_csvField).join(',')).join('\r\n')}\r\n';
