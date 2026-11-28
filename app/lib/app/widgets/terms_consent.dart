import 'package:material_ui/material_ui.dart';

import '../i18n.dart';
import '../legal.dart';

/// Ô đồng ý Điều khoản và Chính sách quyền riêng tư, hiện trước nút đăng ký tài khoản máy chủ.
/// Nút đăng ký chỉ bật khi ô này được chọn; máy chủ cũng từ chối nếu thiếu phiên bản điều khoản.
class TermsConsent extends StatelessWidget {
  const TermsConsent({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          title: Text(tr('Tôi đã đọc và đồng ý Điều khoản sử dụng và Chính sách quyền riêng tư')),
        ),
        if (Legal.siteUrl.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: () => Legal.open('terms'), child: Text(tr('Đọc Điều khoản sử dụng'))),
              TextButton(onPressed: () => Legal.open('privacy'), child: Text(tr('Đọc Chính sách quyền riêng tư'))),
            ],
          ),
      ],
    );
  }
}
