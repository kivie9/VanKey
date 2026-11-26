import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../i18n.dart';
import '../theme.dart';

/// Nút tròn dấu cộng: xoay thành × và bung các lựa chọn thêm mục.
class SpeedDial extends StatefulWidget {
  const SpeedDial({super.key, required this.open, required this.onOpenChanged, required this.onManual, required this.onScan, required this.onImport});
  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onManual;
  final VoidCallback onScan;
  final VoidCallback onImport;

  @override
  State<SpeedDial> createState() => _SpeedDialState();
}

class _SpeedDialState extends State<SpeedDial> {
  bool get _open => widget.open;

  void _run(VoidCallback f) {
    widget.onOpenChanged(false);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.edit_outlined, tr('Nhập tay'), widget.onManual),
      (Icons.qr_code_scanner, tr('Quét QR'), widget.onScan),
      (Icons.file_download_outlined, tr('Nhập từ file'), widget.onImport),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final a in actions.reversed)
          AnimatedSize(
            duration: Timing.fast,
            curve: Curves.easeOut,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Nhãn cũng bấm được (không chỉ icon tròn).
                      // Nền được làm mờ khi menu mở, nên menu dùng màu thẻ bình thường là đủ nổi.
                      Material(
                        color: AppColors.of(context).card,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm + 2)),
                        child: InkWell(
                          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm + 2)),
                          onTap: () => _run(a.$3),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 10), child: Text(a.$2, style: Theme.of(context).textTheme.labelLarge)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton.small(heroTag: a.$2, tooltip: a.$2, backgroundColor: AppColors.of(context).card, foregroundColor: AppColors.of(context).accent, onPressed: () => _run(a.$3), child: Icon(a.$1)),
                    ]),
                  )
                : const SizedBox(width: 0, height: 0),
          ),
        DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.of(context).accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]),
          child: FloatingActionButton(
            heroTag: 'main',
            tooltip: _open ? tr('Đóng') : tr('Thêm mục'),
            onPressed: () => widget.onOpenChanged(!_open),
            child: AnimatedRotation(turns: _open ? 0.125 : 0, duration: Timing.fast, child: const Icon(Icons.add)),
          ),
        ),
      ],
    );
  }
}
