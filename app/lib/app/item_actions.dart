import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/totp/totp.dart';
import '../core/vault/models.dart';
import 'i18n.dart';
import 'screens/item_editor_screen.dart';
import 'screens/qr_show_screen.dart';
import 'theme.dart';
import 'vault_controller.dart';
import 'widgets/common.dart';
import 'widgets/ui.dart';

/// Chỉ mở http(s). Link thiếu scheme ("github.com") được thêm https://.
Future<void> openExternalUrl(BuildContext context, VaultController controller, String raw) async {
  var text = raw.trim();
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(text)) text = 'https://$text';
  final uri = Uri.tryParse(text);
  final messenger = ScaffoldMessenger.of(context);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Link không hợp lệ'))));
    return;
  }
  final ok = await controller.external(() => launchUrl(uri, mode: LaunchMode.externalApplication));
  if (!ok) messenger.showSnackBar(SnackBar(content: Text(tr('Không mở được link'))));
}

/// Nhấn giữ một mục: hiện ngay các thao tác nhanh, khỏi phải mở chi tiết.
Future<void> showItemActions(BuildContext context, VaultController c, Item item) async {
  unawaited(HapticFeedback.mediumImpact());
  final colors = AppColors.of(context);
  final user = (item.valueOf('username') ?? item.valueOf('account') ?? '').trim();
  final password = item.password;
  final url = (item.valueOf('url') ?? '').trim();
  final t = item.totp;
  String? code;
  if (t != null && t.secret.isNotEmpty) {
    try {
      code = Otp.code(t, DateTime.now());
    } on Object {
      code = null; // khóa lỗi: không đưa tùy chọn chép mã
    }
  }
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      Widget act(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ListTile(
            leading: Icon(icon, color: danger ? colors.danger : colors.muted),
            title: Text(label, style: TextStyle(color: danger ? colors.danger : colors.fg)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Avatar.forItem(item),
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: item.subtitle.isEmpty ? null : Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            if (code != null) act(Icons.pin_outlined, tr('Chép mã 2FA'), () => copyText(context, code!, what: tr('Đã chép mã 2FA'))),
            if (user.isNotEmpty) act(Icons.person_outline, tr('Chép tên đăng nhập'), () => copyText(context, user, what: tr('Đã chép tên đăng nhập'))),
            if (password.isNotEmpty) act(Icons.key_rounded, tr('Chép mật khẩu'), () => copyText(context, password, what: tr('Đã chép mật khẩu'))),
            if (url.isNotEmpty) act(Icons.open_in_new_rounded, tr('Mở link'), () => openExternalUrl(context, c, url)),
            act(item.favorite ? Icons.star_border_rounded : Icons.star_rounded, item.favorite ? tr('Bỏ yêu thích') : tr('Yêu thích'), () => c.toggleFavorite(item)),
            act(Icons.edit_outlined, tr('Sửa'), () => navigator.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ItemEditorScreen(controller: c, existing: item)))),
            if (code != null) act(Icons.qr_code_2, tr('Hiện mã QR'), () => navigator.push(MaterialPageRoute<void>(builder: (_) => QrShowScreen.forItem(item)))),
            act(Icons.delete_outline_rounded, tr('Xóa vào thùng rác'), () async {
              final ok = await confirmDialog(
                context,
                title: tr('Chuyển "{p0}" vào thùng rác?', {'p0': item.title}),
                message: tr('Mục sẽ nằm trong thùng rác 30 ngày, bạn có thể khôi phục trong thời gian đó.'),
                confirmLabel: tr('Chuyển vào thùng rác'),
                danger: true,
              );
              if (!ok) return;
              c.trash(item);
              messenger.showSnackBar(SnackBar(
                content: Text(tr('Đã chuyển "{p0}" vào thùng rác', {'p0': item.title})),
                action: SnackBarAction(label: tr('Hoàn tác'), onPressed: () => c.restore(c.data.byId(item.id)!)),
              ));
            }, danger: true),
            const SizedBox(height: Gap.sm),
          ]),
        ),
      );
    },
  );
}
