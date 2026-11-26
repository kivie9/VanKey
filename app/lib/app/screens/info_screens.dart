import 'package:material_ui/material_ui.dart';

import '../widgets/form_layout.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/ui.dart';

const appVersion = '0.1.0';

/// Hỗ trợ: các câu hỏi thường gặp.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faq = [
      (
        tr('Quên mật khẩu kho thì sao?'),
        tr(
          'Dùng mã khôi phục ở màn mở khóa. Nếu mất cả mật khẩu lẫn mã khôi phục thì không ai mở lại được kho, kể cả nhà phát triển, vì dữ liệu mã hóa ngay trên máy.',
        ),
      ),
      (
        tr('Chuyển từ Google Authenticator thế nào?'),
        tr(
          'Trong Google Authenticator chọn Xuất tài khoản, rồi trong VanKey bấm + → Quét QR. Có thể chụp màn hình mã QR và chọn ảnh. Sau khi xong hãy so vài mã với app cũ trước khi xóa app cũ.',
        ),
      ),
      (
        tr('Dữ liệu của tôi nằm ở đâu?'),
        tr(
          'Chỉ trên máy này, đã mã hóa. Chưa có máy chủ nào giữ dữ liệu. Khi bật đồng bộ, nơi lưu chỉ thấy bản mã hóa không đọc được.',
        ),
      ),
      (
        tr('Chế độ "không mật khẩu" có an toàn không?'),
        tr(
          'Kho vẫn mã hóa bằng khóa riêng giữ trong Keystore của điện thoại, nhưng ai mở được khóa màn hình của bạn thì mở được app. Hãy đặt mật khẩu nếu cần chắc chắn hơn.',
        ),
      ),
      (
        tr('Sao lưu thế nào?'),
        tr(
          'Cài đặt → Dữ liệu → Xuất và sao lưu → Sao lưu mã hóa. File chỉ mở lại được bằng mật khẩu hoặc mã khôi phục.',
        ),
      ),
      (
        tr('Vì sao mật khẩu cũ vẫn còn trong lịch sử?'),
        tr(
          'Để bạn dùng lại nếu đổi nhầm. Mỗi mục giữ tối đa 10 mật khẩu gần nhất và chỉ xem được khi kho đã mở.',
        ),
      ),
      (
        tr('Mã 2FA báo sai?'),
        tr(
          'Kiểm tra đồng hồ điện thoại có đặt tự động không: mã TOTP phụ thuộc giờ chính xác. Một số dịch vụ dùng 8 số hoặc chu kỳ khác, VanKey giữ đúng thông số trong link gốc.',
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Hỗ trợ'))),
      body: ListView(
        padding: formPadding(MediaQuery.sizeOf(context).width),
        children: [
          CardList(
            children: [
              for (final q in faq)
                ExpansionTile(
                  title: Text(
                    q.$1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(
                    Gap.lg,
                    0,
                    Gap.lg,
                    Gap.lg,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q.$2,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: AppColors.of(context).muted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Giới thiệu: phiên bản, cách VanKey bảo vệ dữ liệu, giấy phép.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Giới thiệu'))),
    body: ListView(
      padding: formPadding(MediaQuery.sizeOf(context).width),
      children: [
        Text('VanKey', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(tr('Phiên bản {p0} (bản thử nghiệm)', {'p0': appVersion})),
        const SizedBox(height: 16),
        Text(
          tr(
            'Quản lý mật khẩu, khóa và mã 2FA, mã hóa đầu cuối, dùng được khi không có mạng.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('Cách bảo vệ dữ liệu'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Mã hóa XChaCha20-Poly1305, khóa dẫn xuất bằng Argon2id từ mật khẩu của bạn. Chưa có người ngoài rà soát độc lập, nên hãy giữ thêm bản sao lưu mã hóa và mã khôi phục.',
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: Text(tr('Giấy phép mã nguồn mở')),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'VanKey',
            applicationVersion: appVersion,
          ),
        ),
      ],
    ),
  );
}
