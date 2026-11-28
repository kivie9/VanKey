import 'package:material_ui/material_ui.dart';

/// Chiều rộng tối đa của một form. Trên cửa sổ Windows rộng, ô nhập không được kéo dài hết màn hình.
const formMaxWidth = 560.0;

/// Lề của nội dung trang: [narrow] trên điện thoại; trên màn rộng thì căn giữa, rộng tối đa [formMaxWidth]
/// (lề trên và dưới vẫn theo [narrow]).
EdgeInsets formPadding(
  double screenWidth, [
  EdgeInsets narrow = const EdgeInsets.all(16),
]) {
  if (screenWidth <= formMaxWidth + 32) return narrow;
  final side = (screenWidth - formMaxWidth) / 2;
  return narrow.copyWith(left: side, right: side);
}

/// Thanh nút dính đáy trang, rộng bằng nội dung phía trên và căn giữa.
class FormBar extends StatelessWidget {
  const FormBar({super.key, required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: formMaxWidth + padding.horizontal,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}
