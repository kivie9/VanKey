import 'package:material_ui/material_ui.dart';

import '../../core/vault/services.dart';
import '../i18n.dart';
import '../theme.dart';
import 'common.dart';

/// Thẻ đại diện cho nhiều tài khoản cùng một dịch vụ: logo, tên, số tài khoản, bấm để mở hoặc đóng.
class ServiceStackHeader extends StatelessWidget {
  const ServiceStackHeader({super.key, required this.stack, required this.open, required this.onTap, this.compact = false});
  final ServiceStack stack;
  final bool open;
  final VoidCallback onTap;

  /// Cỡ gọn cho lưới trên máy tính.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final count = tr('{p0} tài khoản', {'p0': stack.items.length});
    final ref = serviceOf(stack.items.first);
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? Gap.md : Gap.lg, vertical: compact ? Gap.sm : Gap.md),
          child: Row(children: [
            Avatar(stack.name, size: compact ? 32 : 40, url: ref?.domain ?? ''),
            SizedBox(width: compact ? 10 : Gap.lg),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stack.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: compact ? text.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : text.titleMedium),
                Text(count, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              ]),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: c.muted),
          ]),
        ),
      ),
    );
  }
}
