import 'package:material_ui/material_ui.dart';

/// Chiều rộng tối đa của một form. Trên cửa sổ Windows rộng, ô nhập không được kéo dài hết màn hình.
const formMaxWidth = 560.0;

/// Lề của nội dung form: 16 px trên điện thoại; trên màn rộng thì căn giữa, rộng tối đa [formMaxWidth].
EdgeInsets formPadding(double screenWidth) {
  final side = screenWidth > formMaxWidth + 32
      ? (screenWidth - formMaxWidth) / 2
      : 16.0;
  return EdgeInsets.fromLTRB(side, 16, side, 16);
}
