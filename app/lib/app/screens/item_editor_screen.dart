import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../../core/errors.dart';
import '../../core/security/password_generator.dart';
import '../../core/security/password_strength.dart';
import '../../core/totp/otpauth.dart';
import '../../core/totp/totp.dart';
import '../../core/vault/models.dart';
import '../labels.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/tag_badge.dart';
import '../widgets/ui.dart';
import '../group_actions.dart';
import '../i18n.dart';

/// Chiều rộng tối đa của form: trên cửa sổ Windows rộng, ô nhập không được kéo dài hết màn hình.
const _formMaxWidth = 560.0;

/// Lề ngang: 16 px trên điện thoại; trên màn rộng thì căn form ở giữa, rộng tối đa [_formMaxWidth].
EdgeInsets _formPadding(double w) {
  final side = w > _formMaxWidth + 32 ? (w - _formMaxWidth) / 2 : 16.0;
  return EdgeInsets.fromLTRB(side, 16, side, 16);
}

/// Thêm mục mới, hoặc sửa mục có sẵn ([existing]).
class ItemEditorScreen extends StatefulWidget {
  const ItemEditorScreen({
    super.key,
    required this.controller,
    this.existing,
    this.prefillSecret,
    this.startType,
  });
  final VaultController controller;
  final Item? existing;

  /// Khóa 2FA hoặc link otpauth:// điền sẵn (từ quét QR, Xem nhanh).
  final String? prefillSecret;
  final ItemType? startType;

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

/// Một dòng trường tùy ý (tên do người dùng đặt).
class _CustomRow {
  _CustomRow({String label = '', String value = '', this.secret = false})
    : label = TextEditingController(text: label),
      value = TextEditingController(text: value);
  final TextEditingController label;
  final TextEditingController value;
  bool secret;

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  late ItemType _type;
  final _title = TextEditingController();
  // Ô "Dịch vụ" chỉ để chọn nhanh: dịch vụ được tính từ địa chỉ web và tên, không lưu riêng.
  final _group = TextEditingController();
  final _secret = TextEditingController();
  final _notes =
      TextEditingController(); // ghi chú riêng của mục (khác loại "Ghi chú")
  final _values = <String, TextEditingController>{};
  final _shown = <String>{};
  bool _showTotpKey = false; // khóa 2FA luôn ẩn cho đến khi bấm mắt
  final _unlocked =
      <String>{}; // trường nhiều dòng nhạy cảm đã bấm "Hiện để sửa"
  TotpParams? _parsed; // thông số khi người dùng dán link otpauth
  String? _error;
  int _reminderMonths = 0; // 0 = không nhắc
  final _custom = <_CustomRow>[];

  Item? get _old => widget.existing;

  @override
  void initState() {
    super.initState();
    final o = _old;
    _type = o?.type ?? widget.startType ?? widget.controller.lastType;
    if (o != null) {
      _title.text = o.title;
      _group.text = o.group;
      _secret.text = o.totp?.secret ?? '';
      _parsed = o.totp;
      _reminderMonths = o.reminder?.months ?? 0;
      _notes.text = o.valueOf('notes') ?? '';
      for (final f in o.fields) {
        if (f.key == null)
          _custom.add(
            _CustomRow(label: f.label ?? '', value: f.value, secret: f.secret),
          );
      }
    }
    if (o == null && widget.startType != null) _type = widget.startType!;
    _syncControllers();
    final pre = widget.prefillSecret;
    if (o == null && pre != null) {
      _secret.text = pre;
      _onSecretChanged(pre);
    }
  }

  void _syncControllers() {
    for (final t in ItemTemplates.of(_type)) {
      _values.putIfAbsent(
        t.key,
        () => TextEditingController(text: _old?.valueOf(t.key) ?? ''),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _group.dispose();
    _secret.dispose();
    _notes.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    for (final r in _custom) {
      r.dispose();
    }
    super.dispose();
  }

  /// Chấp nhận cả link otpauth:// lẫn khóa Base32 thô.
  void _onSecretChanged(String v) {
    final text = v.trim();
    if (text.startsWith('otpauth://')) {
      try {
        final a = OtpAuth.parse(text);
        setState(() {
          _parsed = a.toParams();
          _secret.text = a.secret;
          if (_title.text.isEmpty) _title.text = a.title;
          final acc = _values['account'] ?? _values['username'];
          if (acc != null && acc.text.isEmpty) acc.text = a.account;
          _error = null;
        });
      } on VaultException catch (e) {
        setState(
          () => _error = tr('Link không hợp lệ: {p0}', {'p0': e.message}),
        );
      }
    }
  }

  TotpParams? _buildTotp() {
    final s = _secret.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (s.isEmpty) return null;
    final base = _parsed;
    return TotpParams(
      secret: s,
      algorithm: base?.algorithm ?? TotpAlgorithm.sha1,
      digits: base?.digits ?? 6,
      period: base?.period ?? 30,
      kind: base?.kind ?? 'totp',
      counter: base?.counter ?? 0,
    );
  }

  /// Khi SỬA mục có sẵn, trường nhiều dòng nhạy cảm (mã dự phòng, cụm từ khôi phục, ghi chú) bị che cho đến khi người dùng bấm hiện.
  bool _isLocked(String key, TextEditingController ctrl) =>
      _old != null && ctrl.text.isNotEmpty && !_unlocked.contains(key);

  Widget _maskedBlock(String key, String label) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () => setState(() => _unlocked.add(key)),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          color: c.field,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: t.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    Mask.dotsLong,
                    style: t.bodyLarge?.copyWith(
                      letterSpacing: Mask.letterSpacing,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.visibility_outlined, size: 20, color: c.muted),
            const SizedBox(width: Gap.sm),
            Text(
              tr('Hiện để sửa'),
              style: t.labelLarge?.copyWith(color: c.accent),
            ),
          ],
        ),
      ),
    );
  }

  /// Ghi chú của mục (ẩn mặc định như trường bí mật; trùng cách nhập/xuất đang dùng). Loại "Ghi chú" có ô Nội dung riêng.
  List<Field> _notesField() {
    final t = _notes.text.trim();
    if (t.isEmpty || _type == ItemType.note) return const [];
    return [Field(key: 'notes', value: t, secret: true, kind: 'multiline')];
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('Nhập tên cho mục'));
      return;
    }
    final totp = _buildTotp();
    if (totp != null) {
      try {
        Otp.code(totp, DateTime.now()); // kiểm tra khóa hợp lệ trước khi lưu
      } on Object {
        setState(
          () =>
              _error = tr('Khóa 2FA không hợp lệ (chỉ gồm chữ A–Z và số 2–7)'),
        );
        return;
      }
    }
    if (_type == ItemType.totp && totp == null) {
      setState(() => _error = tr('Nhập khóa 2FA'));
      return;
    }
    final c = widget.controller;
    final values = {
      for (final e in _values.entries) e.key: e.value.text.trim(),
    };
    final o = _old;
    final now = DateTime.now().toUtc();
    final customs = [
      for (final r in _custom)
        if (r.label.text.trim().isNotEmpty || r.value.text.trim().isNotEmpty)
          Field(
            label: r.label.text.trim().isEmpty
                ? tr('Trường tùy ý')
                : r.label.text.trim(),
            value: r.value.text.trim(),
            secret: r.secret,
          ),
    ];
    Reminder? reminder() => _reminderMonths == 0
        ? null
        : (o?.reminder?.copyWith(months: _reminderMonths) ??
              Reminder(
                months: _reminderMonths,
                noticeDays: 7,
                lastChangedAt: now,
              ));
    if (o == null) {
      c.rememberType(_type);
      c.upsert(
        Item.create(
          type: _type,
          title: title,
          clock: c.clock,
          values: values,
          customFields: [...customs, ..._notesField()],
          totp: totp,
          group: _group.text.trim(),
        ).copyWith(reminder: reminder()),
      );
    } else {
      var base = o;
      final newPw = values['password'];
      if (newPw != null &&
          o.valueOf('password') != null &&
          newPw != o.password) {
        base = o.changePassword(
          newPw,
          clock: c.clock,
        ); // cất mật khẩu cũ vào lịch sử
      }
      final fields = [
        for (final f in base.fields)
          if (f.key != null && f.key != 'notes')
            (values.containsKey(f.key) ? f.copyWith(value: values[f.key]) : f),
        for (final t in ItemTemplates.of(_type))
          if (!base.fields.any((f) => f.key == t.key) &&
              (values[t.key] ?? '').isNotEmpty)
            Field(
              key: t.key,
              value: values[t.key]!,
              secret: t.secret,
              kind: t.kind,
            ),
        ..._notesField(),
        ...customs,
      ];
      c.upsert(
        base.edit(
          clock: c.clock,
          title: title,
          fields: fields,
          totp: totp,
          group: _group.text.trim(),
          reminder: reminder(),
        ),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final templates = ItemTemplates.of(_type);
    return Scaffold(
      appBar: AppBar(
        title: Text(_old == null ? tr('Thêm mục') : tr('Sửa mục')),
        leading: IconButton(
          tooltip: tr('Hủy'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: LayoutBuilder(builder: (context, box) => ListView(
        padding: _formPadding(box.maxWidth),
        children: [
          if (_old == null) ...[
            // Chọn loại: chỉ icon, cả 7 loại nằm gọn trên một hàng (nhấn giữ để xem tên).
            Row(
              children: [
                for (var i = 0; i < ItemType.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _TypeTile(
                      type: ItemType.values[i],
                      selected: _type == ItemType.values[i],
                      onTap: () => setState(() {
                        _type = ItemType.values[i];
                        _syncControllers();
                      }),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Gap.lg),
          ],
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: tr('Tên')),
          ),
          const SizedBox(height: 12),
          // Thẻ ngay dưới tên: chọn nhanh, có logo chữ cái và màu của thẻ.
          InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () async {
              final v = await pickGroup(
                context,
                widget.controller,
                current: _group.text.trim(),
              );
              if (v != null) setState(() => _group.text = v);
            },
            child: InputDecorator(
              isEmpty: false,
              decoration: InputDecoration(
                labelText: tr('Thẻ'),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: TagBadge(name: _group.text.trim(), color: widget.controller.tagColor(_group.text.trim()), size: 24),
                ),
                suffixIcon: const Icon(Icons.unfold_more_rounded),
              ),
              child: Text(
                _group.text.trim().isEmpty ? tr('Không có thẻ') : _group.text.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final t in templates) ...[
            if (t.secret &&
                t.kind == 'multiline' &&
                _isLocked(t.key, _values[t.key]!))
              _maskedBlock(t.key, L.fieldKey(t.key))
            else
              TextField(
                controller: _values[t.key],
                obscureText:
                    t.secret &&
                    t.kind != 'multiline' &&
                    !_shown.contains(t.key),
                minLines: t.kind == 'multiline' ? 3 : 1,
                maxLines: t.kind == 'multiline' ? 6 : 1,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: t.key == 'password'
                    ? (_) => setState(() {})
                    : null,
                decoration: InputDecoration(
                  labelText: L.fieldKey(t.key),
                  suffixIcon: t.secret && t.kind != 'multiline'
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (t.key == 'password')
                              IconButton(
                                tooltip: tr('Tạo mật khẩu'),
                                icon: const Icon(Icons.auto_fix_high),
                                onPressed: () => setState(() {
                                  _values[t.key]!.text =
                                      PasswordGenerator.generate(length: 20);
                                  _shown.add(t.key);
                                }),
                              ),
                            IconButton(
                              tooltip: _shown.contains(t.key)
                                  ? tr('Ẩn')
                                  : tr('Hiện'),
                              icon: Icon(
                                _shown.contains(t.key)
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _shown.contains(t.key)
                                    ? _shown.remove(t.key)
                                    : _shown.add(t.key),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            if (t.key == 'password' && _values[t.key]!.text.isNotEmpty)
              StrengthMeter(PasswordStrength.estimate(_values[t.key]!.text)),
            const SizedBox(height: 12),
          ],
          if (_type == ItemType.login ||
              _type == ItemType.totp ||
              _type == ItemType.key ||
              _type == ItemType.crypto ||
              _old?.totp != null) ...[
            TextField(
              controller: _secret,
              obscureText: !_showTotpKey,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _onSecretChanged,
              decoration: InputDecoration(
                labelText: _type == ItemType.totp
                    ? tr('Khóa 2FA hoặc link otpauth://')
                    : tr('Khóa 2FA (không bắt buộc)'),
                helperText: tr('Dán khóa Base32 hoặc cả link otpauth://'),
                suffixIcon: IconButton(
                  tooltip: _showTotpKey ? tr('Ẩn') : tr('Hiện'),
                  icon: Icon(
                    _showTotpKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _showTotpKey = !_showTotpKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (templates.any((t) => t.key == 'password')) ...[
            DropdownButtonFormField<int>(
              initialValue: _reminderMonths,
              borderRadius: BorderRadius.circular(Radii.md),
              icon: const Icon(Icons.expand_more_rounded),
              decoration: InputDecoration(labelText: tr('Nhắc đổi mật khẩu')),
              items: [
                DropdownMenuItem(value: 0, child: Text(tr('Không nhắc'))),
                DropdownMenuItem(value: 1, child: Text(tr('Mỗi 1 tháng'))),
                DropdownMenuItem(value: 3, child: Text(tr('Mỗi 3 tháng'))),
                DropdownMenuItem(value: 6, child: Text(tr('Mỗi 6 tháng'))),
                DropdownMenuItem(value: 12, child: Text(tr('Mỗi 12 tháng'))),
              ],
              onChanged: (v) => setState(() => _reminderMonths = v ?? 0),
            ),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < _custom.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _custom[i].label,
                    decoration: InputDecoration(labelText: tr('Tên trường')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _custom[i].value,
                    obscureText: _custom[i].secret,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(labelText: tr('Giá trị')),
                  ),
                ),
                IconButton(
                  tooltip: _custom[i].secret ? tr('Hiện') : tr('Ẩn'),
                  icon: Icon(
                    _custom[i].secret ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _custom[i].secret = !_custom[i].secret),
                ),
                IconButton(
                  tooltip: tr('Xóa trường'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () =>
                      setState(() => _custom.removeAt(i).dispose()),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _custom.add(_CustomRow(secret: true))),
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm trường tùy ý')),
            ),
          ),
          const SizedBox(height: 4),
          if (_type != ItemType.note) ...[
            if (_isLocked('notes', _notes))
              _maskedBlock('notes', tr('Ghi chú'))
            else
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Ghi chú'),
                  hintText: tr('Thông tin thêm cho mục này (tùy chọn)'),
                  alignLabelWithHint: true,
                ),
              ),
            const SizedBox(height: Gap.md),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: Notice(
                _error!,
                tone: NoticeTone.error,
                icon: Icons.error_outline,
              ),
            ),
          const SizedBox(height: 90),
        ],
      )),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.of(context).card,
          border: Border(top: BorderSide(color: AppColors.of(context).line)),
        ),
        child: SafeArea(
          child: Center(
            heightFactor: 1, // chỉ cao bằng hàng nút; thiếu dòng này thanh dưới chiếm hết màn hình
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _formMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.lg,
                  Gap.md,
                  Gap.lg,
                  Gap.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(tr('Hủy')),
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _save,
                        child: Text(tr('Lưu')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ô chọn loại mục: chỉ icon (tên hiện khi nhấn giữ và cho trình đọc màn hình).
class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });
  final ItemType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Tooltip(
      message: L.type(type),
      child: Semantics(
        button: true,
        selected: selected,
        label: L.type(type),
        excludeSemantics: true,
        child: Material(
          color: selected ? c.accentSoft : c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: selected
                ? BorderSide(color: c.accent, width: 1.4)
                : BorderSide.none,
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            onTap: onTap,
            child: SizedBox(
              height: 46,
              child: Center(
                child: Icon(
                  L.typeIcons[type],
                  size: 24,
                  color: selected ? c.accent : c.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
