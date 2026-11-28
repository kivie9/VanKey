import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legal.dart';
import '../widgets/form_layout.dart';

import '../i18n.dart';
import '../theme.dart';
import '../update_check.dart';
import '../widgets/ui.dart';

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
          'Trong Google Authenticator chọn Xuất tài khoản, rồi trong VanKey bấm + → Quét QR. Có thể chụp màn hình mã QR và chọn ảnh. Sau khi xong so vài mã với app cũ trước khi xóa app cũ.',
        ),
      ),
      (
        tr('Dữ liệu của tôi nằm ở đâu?'),
        tr(
          'Trên máy này, đã mã hóa. Khi bật đồng bộ (máy chủ VanKey hoặc Google Drive), nơi lưu chỉ giữ bản mã hóa, không đọc được nếu thiếu mật khẩu hoặc mã khôi phục của bạn.',
        ),
      ),
      (
        tr('Mở bằng vân tay hoặc Windows Hello có an toàn không?'),
        tr(
          'App không cất mật khẩu. Khóa kho được bọc bằng một khóa phần cứng (Android Keystore hoặc Windows Hello trong TPM), chỉ dùng được sau khi bạn xác thực. Ai có vân tay hoặc PIN đã đăng ký trên máy này vẫn mở được, nên bật tự khóa. Đổi vân tay trên máy thì phải nhập lại mật khẩu kho, nên nhớ nó.',
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
      (
        tr('Đồng bộ hoạt động thế nào?'),
        tr(
          'Bật trong Cài đặt → Dữ liệu → Đồng bộ, rồi chọn máy chủ VanKey, Google Drive hoặc một thư mục. Mỗi lần lưu, app gộp thay đổi của các máy rồi gửi bản đã mã hóa đi. Khi mất mạng app vẫn dùng bình thường và đồng bộ lại sau.',
        ),
      ),
      (
        tr('Mất điện thoại thì làm sao?'),
        tr(
          'Trên máy còn lại, vào Cài đặt → Dữ liệu → Đồng bộ → Thiết bị đã đăng nhập rồi gỡ máy bị mất. Máy đó mất quyền truy cập ngay. Nếu nghi bị lộ, đổi mật khẩu kho.',
        ),
      ),
      (
        tr('Xóa tài khoản máy chủ thế nào?'),
        tr(
          'Cài đặt → Dữ liệu → Đồng bộ → Xóa tài khoản. Thao tác này xóa kho trên máy chủ và trên máy này, không hoàn tác được. Xuất bản sao lưu mã hóa trước nếu còn cần dữ liệu.',
        ),
      ),
      (
        tr('Kho đồng bộ được bao nhiêu mục?'),
        tr(
          'Máy chủ VanKey nhận kho tối đa khoảng 1,5 MB, tức vài nghìn mục. Khi vượt giới hạn, việc đồng bộ lên máy chủ sẽ báo lỗi, còn dữ liệu trên máy vẫn an toàn.',
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
            'Mã hóa XChaCha20-Poly1305, khóa dẫn xuất bằng Argon2id từ mật khẩu của bạn. Chưa có người ngoài rà soát độc lập, nên giữ thêm bản sao lưu mã hóa và mã khôi phục.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('Dữ liệu rời khỏi máy khi nào'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(tr('Chỉ khi bạn bật đồng bộ: bản đã mã hóa được gửi tới máy chủ VanKey, Google Drive hoặc thư mục bạn chọn.')),
        const SizedBox(height: 4),
        Text(tr('Kiểm tra mật khẩu rò rỉ: chỉ gửi 5 ký tự đầu của mã băm SHA-1 tới HaveIBeenPwned. Mật khẩu không rời máy.')),
        const SizedBox(height: 4),
        Text(tr('Kiểm tra bản mới: chỉ khi bạn bấm nút, app hỏi GitHub.')),
        const SizedBox(height: 4),
        Text(tr('Không có phân tích hay báo lỗi tự động.')),
        if (Legal.siteUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final (key, label) in [
            ('terms', tr('Điều khoản sử dụng')),
            ('privacy', tr('Chính sách quyền riêng tư')),
            ('delete', tr('Xóa tài khoản và dữ liệu')),
            ('security', tr('Bảo mật và báo lỗ hổng')),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: Text(label),
              onTap: () => Legal.open(key),
            ),
        ],
        const SizedBox(height: 16),
        const _UpdateTile(),
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

/// "Kiểm tra bản mới": chỉ hỏi GitHub khi người dùng bấm, có bản mới thì mở trang tải về.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _busy = false;
  String? _status;
  ReleaseInfo? _newer;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _status = null;
      _newer = null;
    });
    String status;
    ReleaseInfo? newer;
    try {
      final r = await fetchLatestRelease();
      if (isNewerVersion(r.version, appVersion)) {
        newer = r;
        status = tr('Có bản mới {p0}. Bấm để tải về.', {'p0': r.version});
      } else {
        status = tr('Bạn đang dùng bản mới nhất.');
      }
    } catch (_) {
      status = tr('Không kiểm tra được. Kiểm tra mạng rồi thử lại.');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
      _newer = newer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final newer = _newer;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(newer != null ? Icons.download_outlined : Icons.system_update_outlined),
      title: Text(tr('Kiểm tra bản mới')),
      subtitle: _status == null ? null : Text(_status!),
      trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      onTap: _busy
          ? null
          : newer != null
          ? () => launchUrl(newer.page, mode: LaunchMode.externalApplication)
          : _check,
    );
  }
}
