import 'package:material_ui/material_ui.dart';

import '../widgets/form_layout.dart';

import '../theme.dart';
import '../vault_controller.dart';
import '../i18n.dart';

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(tr('Giao diện'))),
      body: ListView(
        padding: formPadding(MediaQuery.sizeOf(context).width),
        children: [
          Text(tr('Chế độ'), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'system',
                label: Text(tr('Hệ thống')),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: 'light',
                label: Text(tr('Sáng')),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: 'dark',
                label: Text(tr('Tối')),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {controller.themeMode},
            onSelectionChanged: (s) => controller.setTheme(s.first),
          ),
          const SizedBox(height: 24),
          Text(tr('Màu nhấn'), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (var i = 0; i < accentColors.length; i++)
                Semantics(
                  button: true,
                  selected: controller.accent == i,
                  label: tr('Màu nhấn {p0}', {'p0': i + 1}),
                  child: InkResponse(
                    onTap: () => controller.setAccent(i),
                    child: Container(
                      width: 48,
                      height: 48,
                      // Vòng chọn lấy đúng màu của swatch (không dùng onSurface: ở giao diện tối nó gần trắng).
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: controller.accent == i
                            ? Border.all(color: Color(accentColors[i]), width: 2)
                            : null,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(accentColors[i]),
                          shape: BoxShape.circle,
                        ),
                        child: controller.accent == i
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
