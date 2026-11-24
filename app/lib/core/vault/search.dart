import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'models.dart';

/// Bỏ dấu tiếng Việt và đưa về chữ thường để tìm kiếm không phân biệt dấu: `Ngân hàng` ~ `ngan hang`.
String foldVietnamese(String s) =>
    unorm.nfd(s.toLowerCase()).replaceAll(RegExp('[̀-ͯ]'), '').replaceAll('đ', 'd');

/// Tìm theo **tên, nhóm, loại và các trường không bí mật**. Tuyệt đối không tìm trong trường bí mật
/// (mật khẩu, khóa, số thẻ...) vì kết quả khớp có thể làm lộ nội dung bí mật.
/// Nhiều từ: mọi từ đều phải xuất hiện (thứ tự bất kỳ).
bool matchesQuery(Item item, String query) {
  final tokens = foldVietnamese(query).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return true;
  final hay = foldVietnamese([
    item.title,
    item.group,
    item.typeName,
    for (final f in item.fields)
      if (!f.secret) f.value,
  ].join('\n'));
  return tokens.every(hay.contains);
}
