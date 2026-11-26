import 'package:material_ui/material_ui.dart';

import '../../core/security/password_generator.dart';
import '../../core/security/password_strength.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import '../i18n.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  double _length = 20;
  bool _upper = true;
  bool _lower = true;
  bool _digits = true;
  bool _symbols = true;
  bool _clear = true;
  late String _pw;

  @override
  void initState() {
    super.initState();
    _pw = _make();
  }

  String _make() {
    try {
      return PasswordGenerator.generate(
        length: _length.round(),
        useUpper: _upper,
        useLower: _lower,
        useDigits: _digits,
        useSymbols: _symbols,
        avoidAmbiguous: _clear,
      );
    } on Object {
      return '';
    }
  }

  void _regen() => setState(() => _pw = _make());

  /// Tô màu theo loại ký tự: chữ cái thường, số, ký hiệu.
  List<TextSpan> _spans(BuildContext context) {
    final c = AppColors.of(context);
    return [
      for (final ch in _pw.characters)
        TextSpan(
          text: ch,
          style: TextStyle(
            color: RegExp('[0-9]').hasMatch(ch)
                ? c.warn
                : (RegExp('[A-Za-z]').hasMatch(ch) ? c.fg : c.accent),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget toggle(String label, bool v, void Function(bool) on) =>
        SwitchListTile(
          title: Text(label),
          value: v,
          onChanged: (x) {
            on(x);
            // Phải còn ít nhất một loại ký tự.
            if (!_upper && !_lower && !_digits && !_symbols) _lower = true;
            _regen();
          },
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Tạo mật khẩu'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText.rich(
                    TextSpan(
                      children: _spans(context),
                      style: text.headlineSmall?.copyWith(
                        fontFamily: Fonts.mono,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        height: 1.4,
                      ),
                    ),
                  ),
                  StrengthMeter(PasswordStrength.estimate(_pw)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      copyText(context, _pw, what: tr('Đã chép mật khẩu')),
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(tr('Chép')),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _regen,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr('Tạo lại')),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.lg,
                Gap.md,
                Gap.sm,
                Gap.sm,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      tr('Độ dài: {p0}', {'p0': _length.round()}),
                      style: text.bodyLarge?.copyWith(
                        color: colors.fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Giảm'),
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: _length > 8
                        ? () => setState(() {
                            _length--;
                            _pw = _make();
                          })
                        : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: _length,
                      min: 8,
                      max: 64,
                      divisions: 56,
                      onChanged: (v) => setState(() {
                        _length = v;
                        _pw = _make();
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Tăng'),
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _length < 64
                        ? () => setState(() {
                            _length++;
                            _pw = _make();
                          })
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          SectionCard(
            children: [
              toggle(tr('Chữ HOA'), _upper, (v) => _upper = v),
              toggle(tr('Chữ thường'), _lower, (v) => _lower = v),
              toggle(tr('Số'), _digits, (v) => _digits = v),
              toggle(tr('Ký hiệu'), _symbols, (v) => _symbols = v),
              toggle(
                tr('Bỏ ký tự dễ nhầm (I, O, l, 0, 1)'),
                _clear,
                (v) => _clear = v,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
