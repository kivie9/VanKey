import 'package:material_ui/material_ui.dart';

/// Bảng màu gợi ý cho thẻ. Mặc định mỗi tên thẻ được tô một màu cố định theo tên (cùng tên luôn cùng màu).
abstract final class TagPalette {
  static const colors = <Color>[
    Color(0xFF4F6BED), // xanh chủ đạo
    Color(0xFF16A34A), // xanh lá
    Color(0xFFEA580C), // cam
    Color(0xFFDB2777), // hồng
    Color(0xFF0891B2), // xanh ngọc
    Color(0xFF7C3AED), // tím
    Color(0xFFCA8A04), // vàng
    Color(0xFF475569), // xám đậm
  ];

  static Color defaultFor(String name) {
    final t = name.trim();
    if (t.isEmpty) return const Color(0xFF94A3B8);
    var h = 0;
    for (final r in t.runes) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    return colors[h % colors.length];
  }
}

/// Logo của thẻ: hình tròn màu với chữ cái đầu của tên. Thẻ chưa có tên thì hiện icon thư mục trống.
class TagBadge extends StatelessWidget {
  const TagBadge({super.key, required this.name, required this.color, this.size = 22});
  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    if (t.isEmpty) {
      return SizedBox.square(dimension: size, child: Icon(Icons.folder_off_outlined, size: size * 0.8, color: const Color(0xFF94A3B8)));
    }
    final letter = String.fromCharCode(t.runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(color: const Color(0xFFFFFFFF), fontSize: size * 0.5, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}
