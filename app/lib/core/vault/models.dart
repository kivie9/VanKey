import '../crypto/csprng.dart';
import '../errors.dart';
import 'hlc.dart';

enum ItemType {
  login,
  totp,
  key,
  crypto,
  card,
  wifi,
  note;

  static ItemType fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => ItemType.note);
}

enum TotpAlgorithm {
  sha1,
  sha256,
  sha512;

  static TotpAlgorithm fromName(String? name) =>
      values.firstWhere((a) => a.name == (name ?? '').toLowerCase(), orElse: () => TotpAlgorithm.sha1);
}

/// Một trường của mục. Trường theo mẫu có [key] ổn định (để giao diện dịch nhãn theo ngôn ngữ);
/// trường người dùng tự thêm có [label].
final class Field {
  const Field({this.key, this.label, required this.value, this.secret = false, this.kind = 'text'});

  final String? key;
  final String? label;
  final String value;

  /// Trường bí mật: không dùng làm dòng phụ, không đưa vào tìm kiếm, ẩn mặc định.
  final bool secret;
  final String kind;

  Field copyWith({String? value}) =>
      Field(key: key, label: label, value: value ?? this.value, secret: secret, kind: kind);

  Map<String, dynamic> toJson() => {
        if (key != null) 'key': key,
        if (label != null) 'label': label,
        'value': value,
        'secret': secret,
        'kind': kind,
      };

  factory Field.fromJson(Map<String, dynamic> j) => Field(
        key: j['key'] as String?,
        label: j['label'] as String?,
        value: (j['value'] as String?) ?? '',
        secret: (j['secret'] as bool?) ?? false,
        kind: (j['kind'] as String?) ?? 'text',
      );

  @override
  bool operator ==(Object other) =>
      other is Field &&
      other.key == key &&
      other.label == label &&
      other.value == value &&
      other.secret == secret &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(key, label, value, secret, kind);
}

final class TotpParams {
  const TotpParams({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.kind = 'totp',
    this.counter = 0,
  });

  /// Loại mã: 'totp' (theo thời gian), 'hotp' (theo bộ đếm), 'steam' (Steam Guard, 5 ký tự).
  final String kind;

  /// Bộ đếm hiện tại (chỉ dùng cho 'hotp').
  final int counter;

  bool get isHotp => kind == 'hotp';
  bool get isSteam => kind == 'steam';

  TotpParams copyWith({int? counter}) =>
      TotpParams(secret: secret, algorithm: algorithm, digits: digits, period: period, kind: kind, counter: counter ?? this.counter);

  /// Base32 chuẩn hóa (chữ hoa, không khoảng trắng, không padding).
  final String secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  Map<String, dynamic> toJson() => {
        'secret': secret,
        'algo': algorithm.name.toUpperCase(),
        'digits': digits,
        'period': period,
        if (kind != 'totp') 'kind': kind,
        if (kind == 'hotp') 'counter': counter,
      };

  factory TotpParams.fromJson(Map<String, dynamic> j) => TotpParams(
        secret: (j['secret'] as String?) ?? '',
        algorithm: TotpAlgorithm.fromName(j['algo'] as String?),
        digits: (j['digits'] as int?) ?? 6,
        period: (j['period'] as int?) ?? 30,
        kind: (j['kind'] == 'hotp' || j['kind'] == 'steam') ? j['kind'] as String : 'totp',
        counter: (j['counter'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is TotpParams &&
      other.kind == kind &&
      other.counter == counter &&
      other.secret == secret &&
      other.algorithm == algorithm &&
      other.digits == digits &&
      other.period == period;

  @override
  int get hashCode => Object.hash(secret, algorithm, digits, period, kind, counter);
}

final class PwHistoryEntry {
  const PwHistoryEntry({required this.value, required this.changedAt});

  final String value;
  final DateTime changedAt;

  Map<String, dynamic> toJson() => {'value': value, 'changedAt': changedAt.toUtc().toIso8601String()};

  factory PwHistoryEntry.fromJson(Map<String, dynamic> j) => PwHistoryEntry(
        value: (j['value'] as String?) ?? '',
        changedAt: DateTime.tryParse((j['changedAt'] as String?) ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  @override
  bool operator ==(Object other) => other is PwHistoryEntry && other.value == value && other.changedAt == changedAt;

  @override
  int get hashCode => Object.hash(value, changedAt);
}

/// Nhắc đổi mật khẩu: sau [months] tháng kể từ [lastChangedAt], báo trước [noticeDays] ngày.
final class Reminder {
  const Reminder({required this.months, required this.noticeDays, required this.lastChangedAt});

  final int months;
  final int noticeDays;
  final DateTime lastChangedAt;

  Reminder copyWith({int? months, int? noticeDays, DateTime? lastChangedAt}) => Reminder(
        months: months ?? this.months,
        noticeDays: noticeDays ?? this.noticeDays,
        lastChangedAt: lastChangedAt ?? this.lastChangedAt,
      );

  Map<String, dynamic> toJson() => {
        'months': months,
        'noticeDays': noticeDays,
        'lastChangedAt': lastChangedAt.toUtc().toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        months: (j['months'] as int?) ?? 3,
        noticeDays: (j['noticeDays'] as int?) ?? 7,
        lastChangedAt: DateTime.tryParse((j['lastChangedAt'] as String?) ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  @override
  bool operator ==(Object other) =>
      other is Reminder && other.months == months && other.noticeDays == noticeDays && other.lastChangedAt == lastChangedAt;

  @override
  int get hashCode => Object.hash(months, noticeDays, lastChangedAt);
}

/// Mẫu trường cho từng loại mục (khớp prototype).
final class FieldTemplate {
  const FieldTemplate(this.key, {this.secret = false, this.kind = 'text'});
  final String key;
  final bool secret;
  final String kind;
}

abstract final class ItemTemplates {
  static List<FieldTemplate> of(ItemType type) => switch (type) {
        ItemType.login => const [
            FieldTemplate('username'),
            FieldTemplate('password', secret: true),
            FieldTemplate('url', kind: 'url'),
            FieldTemplate('backupCodes', secret: true, kind: 'multiline'),
          ],
        ItemType.totp => const [FieldTemplate('account')],
        ItemType.key => const [
            FieldTemplate('service'),
            FieldTemplate('key', secret: true),
            FieldTemplate('expiry'),
          ],
        ItemType.crypto => const [
            FieldTemplate('wallet'),
            FieldTemplate('address'),
            FieldTemplate('seedPhrase', secret: true, kind: 'multiline'),
          ],
        ItemType.card => const [
            FieldTemplate('holder'),
            FieldTemplate('number', secret: true),
            FieldTemplate('expiry'),
            FieldTemplate('cvv', secret: true),
            FieldTemplate('pin', secret: true),
          ],
        ItemType.wifi => const [
            FieldTemplate('ssid'),
            FieldTemplate('password', secret: true),
            FieldTemplate('security'),
          ],
        ItemType.note => const [FieldTemplate('content', secret: true, kind: 'multiline')],
      };
}

/// Một mục trong kho. **Bất biến**: sửa bằng [copyWith] hoặc các hàm `edit...` (tạo HLC mới).
final class Item {
  const Item({
    required this.id,
    required this.typeName,
    required this.title,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
    required this.hlc,
    this.totp,
    this.group = '',
    this.favorite = false,
    this.pwHistory = const [],
    this.reminder,
    this.deletedAt,
    this.extra = const {},
  });

  /// Tạo mục mới, điền sẵn các trường theo mẫu của [type].
  factory Item.create({
    required ItemType type,
    required String title,
    required HlcClock clock,
    Map<String, String> values = const {},
    List<Field> customFields = const [],
    TotpParams? totp,
    String group = '',
    bool favorite = false,
    DateTime? now,
    RandomSource? random,
  }) {
    final t = (now ?? DateTime.now()).toUtc();
    return Item(
      id: uuidV4(random),
      typeName: type.name,
      title: title,
      fields: [
        for (final f in ItemTemplates.of(type))
          if ((values[f.key] ?? '').isNotEmpty || f.key == ItemTemplates.of(type).first.key)
            Field(key: f.key, value: values[f.key] ?? '', secret: f.secret, kind: f.kind),
        ...customFields,
      ],
      totp: totp,
      group: group,
      favorite: favorite,
      createdAt: t,
      updatedAt: t,
      hlc: clock.next().toString(),
    );
  }

  final String id;
  final String typeName;
  final String title;
  final List<Field> fields;
  final TotpParams? totp;
  final String group;
  final bool favorite;
  final List<PwHistoryEntry> pwHistory;
  final Reminder? reminder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Khác `null` nghĩa là mục đang nằm trong thùng rác.
  final DateTime? deletedAt;

  /// Phiên bản của mục (HLC dạng chuỗi). Mỗi lần sửa phải sinh HLC mới.
  final String hlc;

  /// Trường lạ trong JSON, giữ nguyên khi ghi lại.
  final Map<String, dynamic> extra;

  ItemType get type => ItemType.fromName(typeName);
  bool get inTrash => deletedAt != null;
  Hlc get version => Hlc.parse(hlc);

  /// Giá trị của trường theo khóa mẫu (`username`, `password`...), hoặc `null`.
  String? valueOf(String key) {
    for (final f in fields) {
      if (f.key == key) return f.value;
    }
    return null;
  }

  String get password => valueOf('password') ?? '';

  /// Dòng phụ trong danh sách: trường **không bí mật** đầu tiên có giá trị.
  String get subtitle {
    for (final f in fields) {
      if (!f.secret && f.value.isNotEmpty) return f.value;
    }
    return '';
  }

  Item copyWith({
    String? title,
    List<Field>? fields,
    Object? totp = _keep,
    String? group,
    bool? favorite,
    List<PwHistoryEntry>? pwHistory,
    Object? reminder = _keep,
    Object? deletedAt = _keep,
    DateTime? updatedAt,
    String? hlc,
  }) =>
      Item(
        id: id,
        typeName: typeName,
        title: title ?? this.title,
        fields: fields ?? this.fields,
        totp: identical(totp, _keep) ? this.totp : totp as TotpParams?,
        group: group ?? this.group,
        favorite: favorite ?? this.favorite,
        pwHistory: pwHistory ?? this.pwHistory,
        reminder: identical(reminder, _keep) ? this.reminder : reminder as Reminder?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        hlc: hlc ?? this.hlc,
        extra: extra,
      );

  static const Object _keep = Object();

  /// Sửa nội dung và **tạo phiên bản mới** (HLC mới, `updatedAt` mới).
  Item edit({
    required HlcClock clock,
    String? title,
    List<Field>? fields,
    Object? totp = _keep,
    String? group,
    bool? favorite,
    Object? reminder = _keep,
    DateTime? now,
  }) =>
      copyWith(
        title: title,
        fields: fields,
        totp: totp,
        group: group,
        favorite: favorite,
        reminder: reminder,
        updatedAt: (now ?? DateTime.now()).toUtc(),
        hlc: clock.next().toString(),
      );

  /// Đổi mật khẩu: cất mật khẩu cũ vào lịch sử (tối đa [maxHistory]) và tính lại hạn nhắc.
  Item changePassword(String newPassword, {required HlcClock clock, DateTime? now, int maxHistory = 10}) {
    final t = (now ?? DateTime.now()).toUtc();
    final old = password;
    var found = false;
    final newFields = [
      for (final f in fields)
        if (f.key == 'password')
          () {
            found = true;
            return f.copyWith(value: newPassword);
          }()
        else
          f,
    ];
    if (!found) throw const InvalidInputException('mục này không có trường mật khẩu');
    final history = [
      if (old.isNotEmpty) PwHistoryEntry(value: old, changedAt: t),
      ...pwHistory,
    ].take(maxHistory).toList();
    return edit(clock: clock, fields: newFields, now: t).copyWith(
      pwHistory: history,
      reminder: reminder?.copyWith(lastChangedAt: t),
    );
  }

  Item moveToTrash({required HlcClock clock, DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    return copyWith(deletedAt: t, updatedAt: t, hlc: clock.next().toString());
  }

  Item restore({required HlcClock clock, DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    return copyWith(deletedAt: null, updatedAt: t, hlc: clock.next().toString());
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'type': typeName,
        'title': title,
        'fields': fields.map((f) => f.toJson()).toList(),
        if (totp != null) 'totp': totp!.toJson(),
        'group': group,
        'favorite': favorite,
        'pwHistory': pwHistory.map((h) => h.toJson()).toList(),
        if (reminder != null) 'reminder': reminder!.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        'hlc': hlc,
      };

  static const _knownKeys = {
    'id', 'type', 'title', 'fields', 'totp', 'group', 'favorite', 'pwHistory', 'reminder',
    'createdAt', 'updatedAt', 'deletedAt', 'hlc',
  };

  factory Item.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) throw const CorruptVaultException('mục thiếu id');
    DateTime date(Object? v) =>
        DateTime.tryParse((v as String?) ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    List<T> list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
        v is List ? [for (final e in v) if (e is Map<String, dynamic>) f(e)] : <T>[];
    return Item(
      id: id,
      typeName: (j['type'] as String?) ?? 'note',
      title: (j['title'] as String?) ?? '',
      fields: list(j['fields'], Field.fromJson),
      totp: j['totp'] is Map<String, dynamic> ? TotpParams.fromJson(j['totp'] as Map<String, dynamic>) : null,
      group: (j['group'] as String?) ?? '',
      favorite: (j['favorite'] as bool?) ?? false,
      pwHistory: list(j['pwHistory'], PwHistoryEntry.fromJson),
      reminder: j['reminder'] is Map<String, dynamic> ? Reminder.fromJson(j['reminder'] as Map<String, dynamic>) : null,
      createdAt: date(j['createdAt']),
      updatedAt: date(j['updatedAt']),
      deletedAt: j['deletedAt'] == null ? null : date(j['deletedAt']),
      hlc: (j['hlc'] as String?) ?? '',
      extra: {
        for (final e in j.entries)
          if (!_knownKeys.contains(e.key)) e.key: e.value,
      },
    );
  }
}

/// Dấu vết của mục bị **xóa vĩnh viễn**, để việc xóa lan sang thiết bị khác khi đồng bộ.
final class Tombstone {
  const Tombstone({required this.id, required this.deletedAt, required this.hlc});

  final String id;
  final DateTime deletedAt;
  final String hlc;

  Hlc get version => Hlc.parse(hlc);

  Map<String, dynamic> toJson() => {'id': id, 'deletedAt': deletedAt.toUtc().toIso8601String(), 'hlc': hlc};

  factory Tombstone.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) throw const CorruptVaultException('tombstone thiếu id');
    return Tombstone(
      id: id,
      deletedAt: DateTime.tryParse((j['deletedAt'] as String?) ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      hlc: (j['hlc'] as String?) ?? '',
    );
  }
}

/// Toàn bộ dữ liệu bên trong kho.
final class VaultData {
  const VaultData({
    this.schema = currentSchema,
    this.groups = const [],
    this.items = const [],
    this.tombstones = const [],
    this.extra = const {},
  });

  static const currentSchema = 1;

  final int schema;
  final List<String> groups;
  final List<Item> items;
  final List<Tombstone> tombstones;
  final Map<String, dynamic> extra;

  Item? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Thêm mới hoặc thay thế mục (theo id).
  VaultData upsert(Item item) {
    final out = [for (final i in items) if (i.id != item.id) i, item];
    return copyWith(
      items: out,
      groups: item.group.isNotEmpty && !groups.contains(item.group) ? [...groups, item.group] : groups,
      tombstones: [for (final t in tombstones) if (t.id != item.id) t],
    );
  }

  /// Xóa vĩnh viễn: bỏ mục và để lại tombstone.
  VaultData purge(String id, {required HlcClock clock, DateTime? now}) => copyWith(
        items: [for (final i in items) if (i.id != id) i],
        tombstones: [
          for (final t in tombstones) if (t.id != id) t,
          Tombstone(id: id, deletedAt: (now ?? DateTime.now()).toUtc(), hlc: clock.next().toString()),
        ],
      );

  /// Xóa vĩnh viễn các mục nằm trong thùng rác từ [days] ngày trở lên (mặc định 30).
  VaultData purgeExpiredTrash({required DateTime now, required HlcClock clock, int days = 30}) {
    var d = this;
    for (final i in items) {
      final at = i.deletedAt;
      if (at != null && now.toUtc().difference(at).inDays >= days) d = d.purge(i.id, clock: clock, now: now);
    }
    return d;
  }

  VaultData copyWith({List<String>? groups, List<Item>? items, List<Tombstone>? tombstones}) => VaultData(
        schema: schema,
        groups: groups ?? this.groups,
        items: items ?? this.items,
        tombstones: tombstones ?? this.tombstones,
        extra: extra,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'schema': schema,
        'groups': groups,
        'items': items.map((i) => i.toJson()).toList(),
        'tombstones': tombstones.map((t) => t.toJson()).toList(),
      };

  factory VaultData.fromJson(Map<String, dynamic> j) {
    final schema = (j['schema'] as int?) ?? 1;
    if (schema > currentSchema) {
      throw const UnsupportedVersionException('dữ liệu kho dùng lược đồ mới hơn, hãy cập nhật ứng dụng');
    }
    const known = {'schema', 'groups', 'items', 'tombstones'};
    return VaultData(
      schema: schema,
      groups: [for (final g in (j['groups'] as List?) ?? const []) if (g is String) g],
      items: [for (final i in (j['items'] as List?) ?? const []) if (i is Map<String, dynamic>) Item.fromJson(i)],
      tombstones: [for (final t in (j['tombstones'] as List?) ?? const []) if (t is Map<String, dynamic>) Tombstone.fromJson(t)],
      extra: {
        for (final e in j.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }
}
