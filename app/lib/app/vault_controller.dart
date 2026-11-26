import 'demo_data.dart';
import 'constants.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../core/crypto/csprng.dart';
import '../core/crypto/kdf.dart';
import '../core/crypto/recovery_key.dart';
import '../core/errors.dart';
import '../core/sync/cloudflare_sync.dart';
import '../core/sync/folder_sync_provider.dart';
import '../core/sync/sync_provider.dart';
import '../core/sync/sync_service.dart';
import '../core/sync/drive_sync.dart';
import '../core/vault/merge.dart';
import 'google_drive_auth.dart';
import '../core/vault/hlc.dart';
import '../core/vault/models.dart';
import '../core/vault/services.dart';
import '../core/vault/vault_session.dart';
import '../core/vault/vault_storage.dart';
import 'notification_service.dart';
import 'brand.dart';
import 'isolate_ops.dart';
import 'platform_bridge.dart';
import 'theme.dart' show accentColors;
import './i18n.dart';

enum Phase { loading, onboarding, locked, unlocked }

enum GroupBy { group, type, service, none }

enum SortBy { name, updated, created }

enum SyncStatus { off, idle, syncing, error }


/// Giữ kho trong bộ nhớ, mở/khóa, và tự lưu sau mỗi thay đổi (gộp trong ~500 ms).
///
/// Argon2id (~1 giây) luôn chạy trong isolate riêng để giao diện không đứng.
class VaultController extends ChangeNotifier {
  Phase phase = Phase.loading;
  VaultData data = const VaultData();
  bool busy = false;

  /// Lỗi hiển thị cho người dùng (đã dịch), hoặc `null`.
  String? error;

  /// Recovery key vừa tạo, giữ lại cho tới khi người dùng xác nhận đã lưu.
  String? pendingRecovery;

  /// Tự khóa sau bao nhiêu giây khi app ra nền (0 = ngay lập tức).
  int lockAfterSeconds = LockPolicy.never;
  String themeMode = 'light'; // light | dark | system. Mặc định sáng: giao diện tối gần đen khiến màn đầu khó nhìn với người mới
  String language = 'system'; // system | vi | en
  int accent = 1; // chỉ số trong accentColors: 1 = xanh của logo
  GroupBy groupBy = GroupBy.group;
  SortBy sortBy = SortBy.name;
  bool blockScreenshots = true;
  bool showLogos = true;
  ItemType lastType = ItemType.login; // loại mục vừa tạo gần nhất: lần sau chọn sẵn
  Map<String, DateTime> snoozed = {};

  /// Gợi ý dịch vụ người dùng đã trả lời "Không" (`id mục:id dịch vụ`). Chỉ lưu trên máy này.
  Set<String> dismissedServices = {};

  // Làm chậm khi nhập sai mật khẩu liên tiếp (chỉ chặn giao diện; không thay thế độ khó của Argon2id).
  // Lưu trong kho khóa của hệ điều hành để tắt app mở lại không được đếm lại từ đầu.
  int _failures = 0;
  DateTime? _blockedUntil;
  static const _failuresKey = 'vault.unlock.failures';
  bool biometricEnabled = false;

  /// Vân tay vừa bị tắt vì bản cũ cất mật khẩu không an toàn: nhắc người dùng bật lại (Cài đặt > Tài khoản).
  bool bioNeedsReenable = false;
  static const _bioKey = 'vault.bio.passphrase'; // bản cũ / Windows: mật khẩu kho
  static const _bioBlobKey = 'vault.bio.key.v1'; // Android: vault key đã mã hóa bằng khóa Keystore cần vân tay
  final _localAuth = LocalAuthentication();
  DateTime? _pausedAt;
  bool _external = false;

  /// Chỉ còn cho kho cũ đã tạo ở chế độ "không mật khẩu" (khóa nằm trong Android Keystore, app tự mở).
  /// App không còn cho tạo hay chuyển sang chế độ này; kho cũ vẫn mở được và nên đặt mật khẩu trong Cài đặt.
  bool noPassword = false;

  static const _secure = FlutterSecureStorage();
  static const _secretKey = 'vault.device.secret';

  /// Chế độ "Không tự khóa": vault key (32 byte, base64) cất trong Android Keystore để mở app là vào thẳng, không chạy
  /// lại Argon2id. Chỉ hỏi mật khẩu lại sau khi người dùng tự khóa, đổi sang chế độ tự khóa khác, hoặc xóa kho.
  static const _rememberKey = 'vault.remember.key';
  static const _legacyRememberKey = 'vault.remember.passphrase'; // bản trước cất mật khẩu: đổi sang cất khóa ở lần mở đầu

  // ---- Đồng bộ ----
  SyncProvider? provider;
  SyncStatus syncStatus = SyncStatus.off;
  String? syncError;
  DateTime? lastSync;
  List<ItemConflict> conflicts = [];
  SyncState _syncState = const SyncState();
  final CloudflareApi _cfApi = CloudflareApi();
  CloudflareSession? cfSession;
  static const _cfKey = 'cloudflare.session';
  Timer? _syncTimer;

  /// Chỉ để test: thay đăng nhập Google thật và địa chỉ Drive bằng bản giả.
  @visibleForTesting
  DriveAccountAuth Function() driveAuthFactory = GoogleDriveAuth.new;
  @visibleForTesting
  Uri? driveBase;
  DriveAccountAuth? _driveAuth;
  DriveAccountAuth? _pendingDriveAuth; // đã đăng nhập Google nhưng chưa chọn tạo/mở kho (màn đầu tiên)
  Map<String, dynamic>? _syncConfig;
  late File _syncStateFile;

  late File _file;
  late File _settingsFile;
  late HlcClock clock;
  VaultSession? _session;
  Timer? _saveTimer;
  Future<void> _saving = Future.value();

  /// [dir] chỉ để test: thư mục lưu thay cho thư mục của app.
  Future<void> init({Directory? dir}) async {
    dir ??= await getApplicationSupportDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}vankey.vkv');
    final idFile = File('${dir.path}${Platform.pathSeparator}device.id');
    String id;
    if (await idFile.exists()) {
      id = (await idFile.readAsString()).trim();
    } else {
      id = uuidV4().replaceAll('-', '');
      await idFile.writeAsString(id, flush: true);
    }
    _settingsFile = File('${dir.path}${Platform.pathSeparator}${Storage.settingsFile}');
    try {
      if (await _settingsFile.exists()) {
        final j = jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>;
        final v = j[SettingsKey.lockAfter];
        if (v is int && v >= LockPolicy.never && v <= LockPolicy.maxAutoLockSeconds) lockAfterSeconds = v;
        final lg = j[SettingsKey.language];
        if (lg == LangCode.vi || lg == LangCode.en || lg == LangCode.system) language = lg as String;
        final t = j[SettingsKey.theme];
        if (t == 'light' || t == 'dark' || t == 'system') themeMode = t as String;
        final a = j[SettingsKey.accent];
        if (a is int && a >= 0 && a < accentColors.length) accent = a;
        final sc = j[SettingsKey.sync];
        if (sc is Map<String, dynamic>) _syncConfig = sc;
        final sn = j[SettingsKey.snooze];
        if (sn is Map<String, dynamic>) {
          snoozed = {for (final e in sn.entries) if (e.value is String && DateTime.tryParse(e.value as String) != null) e.key: DateTime.parse(e.value as String)};
        }
        final ds = j[SettingsKey.dismissedServices];
        if (ds is List) dismissedServices = ds.whereType<String>().toSet();
        final so = j[SettingsKey.sortBy];
        if (so is String) sortBy = SortBy.values.firstWhere((e) => e.name == so, orElse: () => SortBy.name);
        final lt = j[SettingsKey.lastType];
        if (lt is String) lastType = ItemType.fromName(lt);
        if (j[SettingsKey.showLogos] is bool) showLogos = j[SettingsKey.showLogos] as bool;
        BrandConfig.enabled = showLogos;
        if (j[SettingsKey.blockScreenshots] is bool) blockScreenshots = j[SettingsKey.blockScreenshots] as bool;
        final g = j[SettingsKey.groupBy];
        if (g is String) groupBy = GroupBy.values.firstWhere((e) => e.name == g, orElse: () => GroupBy.group);
      }
    } on Object {
      // Cài đặt hỏng thì dùng mặc định.
    }
    _syncStateFile = File('${dir.path}${Platform.pathSeparator}sync_state.json');
    _applySyncConfig();
    await _restoreCloudflare();
    await _loadSyncState();
    await PlatformBridge.setSecure(on: blockScreenshots);
    await _dropLegacyBio();
    await _loadFailures();
    biometricEnabled = (await _readBio()) != null;
    clock = HlcClock(node: id);
    if (!await _file.exists()) {
      phase = Phase.onboarding;
      notifyListeners();
      return;
    }
    final secret = await _readSecret();
    if (secret != null) {
      final ok = await _unlock((b) => isoOpenPassphrase(b, secret), trackFailures: false);
      if (ok) {
        noPassword = true;
        notifyListeners();
        return;
      }
      await _deleteSecret(); // bí mật cũ không còn khớp: quay về nhập mật khẩu
    }
    if (lockAfterSeconds == LockPolicy.never && await _openRemembered()) return;
    phase = Phase.locked;
    error = null;
    notifyListeners();
  }

  Future<String?> _readSecret() async {
    try {
      return await _secure.read(key: _secretKey);
    } on Object {
      return null;
    }
  }

  Future<void> _deleteSecret() async {
    try {
      await _secure.delete(key: _secretKey);
    } on Object {
      // Không xóa được thì lần sau mở không khớp sẽ tự thử lại.
    }
  }

  Future<void> _loadFailures() async {
    final raw = await _readStored(_failuresKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final n = j['n'];
      if (n is int && n > 0) _failures = n;
      final until = j['until'];
      final t = until is String ? DateTime.tryParse(until) : null;
      // Không tin thời điểm quá xa trong tương lai (đồng hồ máy bị chỉnh lùi rồi chỉnh lại): giới hạn ở mức chờ tối đa.
      final cap = DateTime.now().add(const Duration(seconds: LockPolicy.maxWaitSeconds));
      if (t != null) _blockedUntil = t.isAfter(cap) ? cap : t;
    } on Object {
      // Dữ liệu hỏng thì bỏ qua.
    }
  }

  Future<void> _saveFailures() async {
    try {
      if (_failures == 0 && _blockedUntil == null) {
        await _secure.delete(key: _failuresKey);
      } else {
        await _secure.write(key: _failuresKey, value: jsonEncode({'n': _failures, 'until': _blockedUntil?.toUtc().toIso8601String()}));
      }
    } on Object {
      // Không ghi được thì vẫn chặn trong phiên này.
    }
  }

  Future<String?> _readStored(String key) async {
    try {
      return await _secure.read(key: key);
    } on Object {
      return null;
    }
  }

  /// Mở kho bằng khóa đã ghi nhớ. Khóa không còn khớp (kho đã xoay khóa ở máy khác) thì bỏ và hỏi mật khẩu.
  Future<bool> _openRemembered() async {
    final stored = await _readStored(_rememberKey);
    if (stored != null) {
      Uint8List? key;
      try {
        key = base64Decode(stored);
      } on FormatException {
        key = null;
      }
      final k = key;
      if (k != null && await _unlock((b) => isoOpenKey(b, k), trackFailures: false)) {
        k.fillRange(0, k.length, 0);
        return true;
      }
      await _forget();
      return false;
    }
    // Bản trước cất mật khẩu: mở bằng mật khẩu đó một lần (chậm), rồi đổi sang cất khóa.
    final legacy = await _readStored(_legacyRememberKey);
    if (legacy == null) return false;
    final ok = await _unlock((b) => isoOpenPassphrase(b, legacy), trackFailures: false);
    await _forget();
    if (ok) await _remember();
    return ok;
  }

  /// Ghi nhớ vault key của kho đang mở, chỉ khi đang ở chế độ "Không tự khóa".
  Future<void> _remember() async {
    final s = _session;
    if (lockAfterSeconds != LockPolicy.never || s == null || s.isClosed) return;
    final key = s.exportKey();
    try {
      await _secure.write(key: _rememberKey, value: base64Encode(key));
    } on Object {
      // Không ghi được thì lần sau mở app sẽ hỏi mật khẩu như cũ.
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> _forget() async {
    for (final k in [_rememberKey, _legacyRememberKey]) {
      try {
        await _secure.delete(key: k);
      } on Object {
        // bỏ qua
      }
    }
  }

  /// Lời báo (đã dịch) nếu [password] chưa đủ để làm mật khẩu mới, hoặc `null` nếu đạt. Xem [AccountPolicy.checkNewPassword].
  static String? newPasswordError(String password) => AccountPolicy.newPasswordError(password);

  /// Chuyển sang chế độ có mật khẩu. Trả lời báo nếu mật khẩu chưa đủ mạnh (khi đó không đổi gì).
  Future<String?> setPassword(String passphrase) async {
    final weak = newPasswordError(passphrase);
    if (weak != null) return weak;
    final s = _session!;
    final updated = await isoRewrap(s, passphrase, Argon2Params.standard);
    s.close();
    _session = updated;
    await _writeNow();
    await _deleteSecret();
    await disableBiometric();
    await _forget();
    await _remember();
    noPassword = false;
    notifyListeners();
    return null;
  }

  Future<bool> verifyPassphrase(String passphrase) async {
    final bytes = await VaultStorage.read(_file);
    if (bytes == null) return false;
    try {
      final probe = await isoOpenPassphrase(bytes, passphrase);
      probe.close();
      return true;
    } on AuthenticationFailedException {
      return false;
    }
  }

  /// Đổi mật khẩu kho (phải nhập đúng mật khẩu hiện tại). Trả về lỗi để hiển thị, hoặc null nếu thành công.
  /// Đang đăng nhập máy chủ thì đổi luôn mật khẩu tài khoản trên máy chủ (một mật khẩu cho cả hai), TRƯỚC khi đổi
  /// trên máy: máy chủ không đổi được thì không đổi gì, tránh lệch mật khẩu giữa máy và máy chủ.
  Future<String?> changeVaultPassword(String current, String next) async {
    final weak = newPasswordError(next);
    if (weak != null) return weak;
    if (!await verifyPassphrase(current)) return tr('Mật khẩu hiện tại không đúng');
    final p = provider;
    final user = _serverUsername;
    if (p is CloudflareSync && user != null) {
      try {
        final fresh = await isoAuthKey(user, next);
        await _withLegacyKey(user, current, (k) => p.changeAuthKey(k, fresh));
      } on CloudflareApiException catch (e) {
        // wrong_password: tài khoản cũ có mật khẩu tài khoản khác mật khẩu kho; khi đó chỉ đổi mật khẩu kho như trước.
        if (e.code != 'wrong_password') return tr('Máy chủ chưa đổi được mật khẩu: {p0}', {'p0': e.message});
      } on SyncAuthException catch (e) {
        return tr('Máy chủ chưa đổi được mật khẩu: {p0}', {'p0': e.message});
      } on SyncNetworkException catch (e) {
        return tr('Không kết nối được máy chủ ({p0}). Mật khẩu chưa được đổi.', {'p0': e.message});
      }
    }
    return setPassword(next);
  }

  /// Tên đăng nhập máy chủ đang dùng, nếu có.
  String? get _serverUsername {
    final fromSession = cfSession?.username ?? '';
    if (fromSession.isNotEmpty) return fromSession;
    final fromConfig = _syncConfig?['username'];
    return fromConfig is String && fromConfig.isNotEmpty ? fromConfig : null;
  }

  /// Xóa hẳn tài khoản trên máy chủ (kho trên máy chủ, mọi thiết bị) rồi xóa kho trên máy này và về màn đầu.
  /// Cần nhập mật khẩu. Không hoàn tác được. Trả về lỗi để hiển thị, hoặc null nếu đã xóa.
  Future<String?> deleteServerAccount(String password) async {
    final p = provider;
    final user = _serverUsername;
    if (p is! CloudflareSync || user == null) return tr('Chưa đăng nhập tài khoản máy chủ.');
    try {
      await _withLegacyKey(user, password, p.deleteAccount);
    } on CloudflareApiException catch (e) {
      return e.code == 'wrong_password' ? tr('Mật khẩu không đúng') : e.message;
    } on SyncAuthException catch (e) {
      return e.message;
    } on SyncNetworkException catch (e) {
      return tr('Không kết nối được máy chủ ({p0}). Tài khoản chưa bị xóa.', {'p0': e.message});
    }
    try {
      await _secure.delete(key: _cfKey);
    } on Object {
      // bỏ qua
    }
    cfSession = null;
    await disableSync();
    await resetVault();
    return null;
  }

  /// Tạo mã khôi phục mới (mã cũ mất hiệu lực) và trả về để hiển thị một lần.
  Future<String> newRecoveryKey() async {
    final rec = await _session!.regenerateRecoveryKey();
    await _writeNow();
    return rec.formatted;
  }

  /// Xóa toàn bộ kho trên máy này và bắt đầu lại.
  Future<void> resetVault() async {
    _saveTimer?.cancel();
    _session?.close();
    _session = null;
    for (final f in [_file, File('${_file.path}.bak'), File('${_file.path}.tmp')]) {
      if (await f.exists()) await f.delete();
    }
    await _deleteSecret();
    await disableBiometric();
    await _forget();
    _failures = 0;
    _blockedUntil = null;
    await _saveFailures();
    data = const VaultData();
    noPassword = false;
    error = null;
    phase = Phase.onboarding;
    notifyListeners();
  }

  // ---- Tạo / mở / khóa ----

  Future<void> createVault(String passphrase) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      // Đo máy này để chọn tham số Argon2id vừa sức (nằm trong isolate nên không đứng giao diện).
      final (session, recovery) = await isoCreateCalibrated(passphrase);
      session.payload = const VaultData().toJson();
      _session = session;
      await _writeNow();
      await _remember();
      pendingRecovery = recovery.formatted;
    } catch (e) {
      error = tr('Không tạo được kho: {p0}', {'p0': e});
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Người dùng xác nhận đã lưu recovery key → vào app.
  void confirmRecoverySaved() {
    pendingRecovery = null;
    data = VaultData.fromJson(_session!.payload);
    phase = Phase.unlocked;
    notifyListeners();
    if (provider != null) unawaited(syncNow()); // tài khoản máy chủ vừa tạo: đẩy kho lên ngay
  }

  Future<bool> unlockWithPassphrase(String passphrase) async {
    final ok = await _unlock((bytes) => isoOpenPassphrase(bytes, passphrase));
    if (ok) await _remember();
    return ok;
  }

  Future<bool> unlockWithRecovery(String recoveryText) async {
    final RecoveryKey key;
    try {
      key = RecoveryKey.parse(recoveryText);
    } on VaultException {
      error = tr('Recovery key không đúng định dạng');
      notifyListeners();
      return false;
    }
    return _unlock((bytes) => isoOpenRecovery(bytes, key));
  }

  Future<bool> _unlock(Future<VaultSession> Function(Uint8List) open, {bool trackFailures = true}) async {
    final wait = _blockedUntil?.difference(DateTime.now());
    if (trackFailures && wait != null && !wait.isNegative) {
      error = tr('Nhập sai nhiều lần. Thử lại sau {p0} giây.', {'p0': wait.inSeconds + 1});
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final bytes = await VaultStorage.read(_file);
      if (bytes == null) {
        error = tr('Không thấy file kho');
        return false;
      }
      final session = await open(bytes);
      _session = session;
      data = VaultData.fromJson(session.payload).purgeExpiredTrash(now: DateTime.now(), clock: clock);
      phase = Phase.unlocked;
      unawaited(Future<void>.delayed(Duration.zero, syncNow));
      _scheduleNotifications();
      if (_failures > 0 || _blockedUntil != null) {
        _failures = 0;
        _blockedUntil = null;
        await _saveFailures();
      }
      return true;
    } on AuthenticationFailedException {
      error = tr('Sai mật khẩu, hoặc file kho đã bị sửa');
      if (trackFailures && ++_failures >= LockPolicy.freeAttempts) {
        final secs = LockPolicy.waitSecondsAfter(_failures);
        _blockedUntil = DateTime.now().add(Duration(seconds: secs));
        error = tr('Sai mật khẩu. Chờ {p0} giây trước khi thử lại.', {'p0': secs});
      }
      if (trackFailures) await _saveFailures();
      return false;
    } on VaultException catch (e) {
      error = tr('Không mở được kho: {p0}', {'p0': e.message});
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> lock() async {
    if (noPassword) return; // không có mật khẩu thì khóa cũng vô nghĩa
    await _forget(); // tự khóa thì lần mở sau phải nhập mật khẩu
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    if (_session != null && phase == Phase.unlocked) await _writeNow();
    _session?.close();
    _session = null;
    data = const VaultData();
    phase = Phase.locked;
    error = null;
    notifyListeners();
  }

  // ---- Gợi ý dịch vụ cho mục chưa có địa chỉ web ----

  /// Gợi ý cho một mục, trừ khi người dùng đã từ chối.
  KnownService? serviceSuggestionFor(Item item) {
    final s = suggestService(item);
    return s == null || dismissedServices.contains('${item.id}:${s.id}') ? null : s;
  }

  List<(Item, KnownService)> get serviceSuggestions => [
        for (final i in data.items)
          if (serviceSuggestionFor(i) case final s?) (i, s),
      ];

  Future<void> dismissServiceSuggestion(Item item, KnownService service) =>
      _updateSettings(() => dismissedServices = {...dismissedServices, '${item.id}:${service.id}'});

  /// Người dùng xác nhận gợi ý: điền địa chỉ web của dịch vụ. Tên và các trường khác giữ nguyên.
  void applyService(Item item, KnownService service) {
    final current = data.byId(item.id);
    if (current == null || (current.valueOf('url') ?? '').trim().isNotEmpty) return;
    final url = Field(key: 'url', value: service.domains.first, kind: 'url');
    final fields = current.valueOf('url') == null
        ? [...current.fields, url]
        : [for (final f in current.fields) f.key == 'url' ? url : f];
    upsert(current.edit(clock: clock, fields: fields));
  }

  // ---- Nhắc nhở ----

  Future<void> snooze(String key, int days) =>
      _updateSettings(() => snoozed = {...snoozed, key: DateTime.now().add(Duration(days: days))});

  Timer? _notifyTimer;

  void _scheduleNotifications() {
    _notifyTimer?.cancel();
    _notifyTimer = Timer(Timing.notifyDebounce, () async {
      try {
        await NotificationService.instance.reschedule(data.items.where((i) => !i.inTrash));
      } on Object {
        // Không đặt được lịch thì thôi, không ảnh hưởng dữ liệu.
      }
    });
  }

  // ---- Vân tay ----
  //
  // Android: vault key được mã hóa bằng khóa AES trong Keystore, chỉ dùng được sau khi BiometricPrompt xác thực
  // (BiometricVault.kt). Không cất mật khẩu; vá app hay root máy cũng không lấy được vault key nếu không có vân tay.
  // Nền tảng khác (Windows Hello): chưa gắn được với khóa, vẫn cất mật khẩu trong kho khóa của hệ điều hành và
  // dùng xác thực sinh trắc như một lớp chặn của app.

  bool get _bioBound => Platform.isAndroid;

  Future<String?> _readBio() => _readStored(_bioBound ? _bioBlobKey : _bioKey);

  /// Bản trước trên Android cất mật khẩu dạng đọc được (chỉ chặn bằng giao diện): xóa ngay, người dùng bật lại.
  Future<void> _dropLegacyBio() async {
    if (!_bioBound || await _readStored(_bioKey) == null) return;
    try {
      await _secure.delete(key: _bioKey);
    } on Object {
      // bỏ qua
    }
    bioNeedsReenable = true;
  }

  Future<bool> biometricAvailable() async {
    if (_bioBound) return PlatformBridge.bioAvailable();
    try {
      return await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  /// Bật mở khóa bằng vân tay: xác minh mật khẩu hiện tại rồi cất (Android: vault key đã bọc bằng khóa Keystore).
  Future<String?> enableBiometric(String passphrase) async {
    final bytes = await VaultStorage.read(_file);
    if (bytes == null) return tr('Không thấy file kho');
    final VaultSession probe;
    try {
      probe = await isoOpenPassphrase(bytes, passphrase);
    } on AuthenticationFailedException {
      return tr('Mật khẩu không đúng');
    }
    try {
      if (_bioBound) {
        final key = probe.exportKey();
        try {
          final blob = await external(() => PlatformBridge.bioEncrypt(key, title: tr('Xác nhận để bật mở khóa bằng vân tay'), cancel: tr('Hủy')));
          await _secure.write(key: _bioBlobKey, value: base64Encode(blob));
        } finally {
          key.fillRange(0, key.length, 0);
        }
      } else {
        final ok = await external(() => _localAuth.authenticate(localizedReason: tr('Xác nhận để bật mở khóa bằng vân tay'), biometricOnly: true));
        if (!ok) return tr('Chưa xác thực được vân tay');
        await _secure.write(key: _bioKey, value: passphrase);
      }
    } on BioException catch (e) {
      return e.code == 'canceled' ? tr('Chưa xác thực được vân tay') : tr('Không bật được: {p0}', {'p0': e.message ?? e.code});
    } on Object catch (e) {
      return tr('Không bật được: {p0}', {'p0': e});
    } finally {
      probe.close();
    }
    biometricEnabled = true;
    bioNeedsReenable = false;
    notifyListeners();
    return null;
  }

  Future<void> disableBiometric() async {
    for (final k in [_bioKey, _bioBlobKey]) {
      try {
        await _secure.delete(key: k);
      } on Object {
        // bỏ qua
      }
    }
    await PlatformBridge.bioDelete();
    biometricEnabled = false;
    notifyListeners();
  }

  Future<bool> unlockWithBiometric() async {
    final stored = await _readBio();
    if (stored == null) return false;
    if (!_bioBound) {
      try {
        final ok = await external(() => _localAuth.authenticate(localizedReason: tr('Mở khóa VanKey'), biometricOnly: true));
        if (!ok) return false;
      } on Object {
        return false;
      }
      final opened = await _unlock((b) => isoOpenPassphrase(b, stored), trackFailures: false);
      if (!opened) await disableBiometric(); // mật khẩu đã đổi: bỏ vân tay cũ
      if (opened) await _remember();
      return opened;
    }
    final Uint8List key;
    try {
      final blob = base64Decode(stored);
      key = await external(() => PlatformBridge.bioDecrypt(blob, title: tr('Mở khóa VanKey'), cancel: tr('Dùng mật khẩu')));
    } on BioException catch (e) {
      if (e.code == 'invalidated' || e.code == 'corrupt') {
        await disableBiometric();
        error = tr('Vân tay trên máy đã thay đổi. Hãy nhập mật khẩu rồi bật lại mở khóa bằng vân tay.');
        notifyListeners();
      }
      return false;
    } on FormatException {
      await disableBiometric();
      return false;
    }
    final opened = await _unlock((b) => isoOpenKey(b, key), trackFailures: false);
    key.fillRange(0, key.length, 0);
    if (!opened) await disableBiometric(); // kho đã xoay khóa ở máy khác: bỏ vân tay cũ
    if (opened) await _remember();
    return opened;
  }

  // ---- Đồng bộ ----

  void _applySyncConfig() {
    final c = _syncConfig;
    if (c != null && c['type'] == 'folder' && c['path'] is String) {
      provider = FolderSyncProvider(Directory(c['path'] as String));
      syncStatus = SyncStatus.idle;
    } else if (c != null && c['type'] == 'cloudflare') {
      provider = null; // được dựng lại ở _restoreCloudflare sau khi đọc phiên từ Keystore
      syncStatus = SyncStatus.idle;
    } else if (c != null && c['type'] == 'drive') {
      // Token Google được lấy lười khi đồng bộ (khôi phục phiên đã đăng nhập, không hiện giao diện).
      _driveAuth = driveAuthFactory();
      provider = DriveSync(_driveAuth!, base: driveBase);
      syncStatus = SyncStatus.idle;
    } else {
      provider = null;
      syncStatus = SyncStatus.off;
    }
  }

  // ---- Cloudflare ----

  static String get _deviceName => Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : Platform.operatingSystem);

  /// Chỉ cho phép HTTPS, trừ máy cục bộ (để thử). Chặn gửi đăng nhập qua mạng không mã hóa.
  static bool isAllowedServerUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasAuthority || u.host.isEmpty) return false;
    if (u.scheme == ServerPolicy.secureScheme) return true;
    return u.scheme == ServerPolicy.devScheme && ServerPolicy.devHosts.contains(u.host);
  }

  Future<void> _restoreCloudflare() async {
    if (_syncConfig?['type'] != 'cloudflare') return;
    try {
      final raw = await _secure.read(key: _cfKey);
      if (raw == null) {
        syncStatus = SyncStatus.error;
        syncError = tr('Cần đăng nhập lại vào máy chủ.');
        return;
      }
      cfSession = CloudflareSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      provider = CloudflareSync(_cfApi, cfSession!, onSession: _saveCfSession);
    } on Object {
      syncStatus = SyncStatus.error;
      syncError = tr('Cần đăng nhập lại vào máy chủ.');
    }
  }

  void _saveCfSession(CloudflareSession s) {
    cfSession = s;
    unawaited(_secure.write(key: _cfKey, value: jsonEncode(s.toJson())).catchError((Object _) {}));
  }

  /// Đăng nhập (hoặc đăng ký) tài khoản máy chủ và bật đồng bộ. Trả về thông báo lỗi, hoặc null nếu thành công.
  Future<String?> signInCloudflare({required String url, required String username, required String password, required bool register, String registerCode = ''}) async {
    final base = url.trim();
    if (!isAllowedServerUrl(base)) return tr('Địa chỉ máy chủ phải bắt đầu bằng https://');
    final name = AccountPolicy.normalizeUsername(username);
    if (name == null) return _badUsername;
    if (register) {
      final weak = newPasswordError(password);
      if (weak != null) return weak;
    }
    try {
      final s = register
          ? await _cfApi.register(base, name, await isoAuthKey(name, password), _deviceName, registerCode: registerCode.trim())
          : await _cfLogin(base, name, password);
      _saveCfSession(s);
      await _updateSettings(() => _syncConfig = {'type': 'cloudflare', 'url': base, 'username': s.username.isEmpty ? name : s.username});
      provider = CloudflareSync(_cfApi, s, onSession: _saveCfSession);
      syncStatus = SyncStatus.idle;
      _syncState = const SyncState();
      notifyListeners();
      unawaited(syncNow());
      return null;
    } on CloudflareApiException catch (e) {
      return _apiText(e);
    } on SyncNetworkException catch (e) {
      return tr('Không kết nối được máy chủ ({p0}).', {'p0': e.message});
    }
  }

  String get _badUsername => tr('Tên đăng nhập gồm 3 đến 32 ký tự: chữ thường, số, dấu chấm, gạch dưới hoặc gạch ngang.');

  /// Đăng nhập máy chủ. Tài khoản tạo trước khi mật khẩu được chuẩn hóa NFKC có thể đang dùng khóa cũ: thử khóa cũ,
  /// đúng thì đổi khóa trên máy chủ sang khóa mới để từ đó mọi thiết bị (mọi kiểu bàn phím) đều đăng nhập được.
  Future<CloudflareSession> _cfLogin(String base, String name, String password) async {
    final key = await isoAuthKey(name, password);
    try {
      return await _cfApi.login(base, name, key, _deviceName);
    } on CloudflareApiException catch (e) {
      if (e.code != 'invalid_credentials' || !CloudflareApi.hasLegacyAuthKey(password)) rethrow;
      final legacy = await isoLegacyAuthKey(name, password);
      final CloudflareSession s;
      try {
        s = await _cfApi.login(base, name, legacy, _deviceName);
      } on CloudflareApiException {
        throw e; // báo lỗi của lần thử chính
      }
      try {
        final sync = CloudflareSync(_cfApi, s);
        await sync.changeAuthKey(legacy, key);
        return sync.session; // phiên có thể đã được làm mới trong lúc đổi
      } on Object {
        return s; // chưa chuyển được thì lần sau thử lại; vẫn đăng nhập được bằng khóa cũ
      }
    }
  }

  /// Gọi thao tác cần nhập lại mật khẩu; máy chủ báo sai mà mật khẩu có dạng cũ khác thì thử lại bằng khóa cũ.
  Future<void> _withLegacyKey(String user, String password, Future<void> Function(String authKey) call) async {
    try {
      await call(await isoAuthKey(user, password));
    } on CloudflareApiException catch (e) {
      if (e.code != 'wrong_password' || !CloudflareApi.hasLegacyAuthKey(password)) rethrow;
      try {
        await call(await isoLegacyAuthKey(user, password));
      } on CloudflareApiException {
        throw e;
      }
    }
  }

  String _apiText(CloudflareApiException e) =>
      e.retryAfter != null ? tr('{p0} (chờ {p1} giây)', {'p0': e.message, 'p1': e.retryAfter!}) : e.message;

  /// Tạo tài khoản máy chủ VÀ kho mới bằng MỘT mật khẩu: đăng ký → tạo kho → (sau khi lưu mã khôi phục) đẩy kho lên.
  /// Trả về lỗi hiển thị, hoặc null nếu thành công (khi đó [pendingRecovery] có mã khôi phục cần người dùng lưu).
  Future<String?> signUpWithServer({required String url, required String username, required String password, String registerCode = ''}) async {
    final base = url.trim();
    if (!isAllowedServerUrl(base)) return tr('Địa chỉ máy chủ phải bắt đầu bằng https://');
    final name = AccountPolicy.normalizeUsername(username);
    if (name == null) return _badUsername;
    final weak = newPasswordError(password);
    if (weak != null) return weak;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final authKey = await isoAuthKey(name, password);
      final s = await _cfApi.register(base, name, authKey, _deviceName, registerCode: registerCode.trim());
      return await _createVaultForAccount(base, name, password, s);
    } on CloudflareApiException catch (e) {
      return _apiText(e);
    } on SyncNetworkException catch (e) {
      return tr('Không kết nối được máy chủ ({p0}).', {'p0': e.message});
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Tạo kho mới cho tài khoản vừa đăng ký (hoặc tài khoản chưa có kho trên máy chủ), mở bằng chính [password].
  Future<String?> _createVaultForAccount(String base, String username, String password, CloudflareSession s) async {
    try {
      final (session, recovery) = await isoCreateCalibrated(password);
      session.payload = const VaultData().toJson();
      _session = session;
      await _writeNow();
      _saveCfSession(s);
      await _updateSettings(() => _syncConfig = {'type': 'cloudflare', 'url': base, 'username': s.username.isEmpty ? username : s.username});
      provider = CloudflareSync(_cfApi, s, onSession: _saveCfSession);
      syncStatus = SyncStatus.idle;
      _syncState = const SyncState();
      await _remember();
      pendingRecovery = recovery.formatted;
      return null;
    } on Object catch (e) {
      return tr('Không tạo được kho: {p0}', {'p0': e});
    }
  }

  /// Đăng nhập bằng tên đăng nhập và mật khẩu. Kho trên máy chủ được mở bằng chính mật khẩu đó.
  /// [vaultMismatch] = true khi đăng nhập được nhưng mật khẩu không mở được kho (kho đặt mật khẩu khác từ trước).
  Future<({String? error, bool vaultMismatch})> signInWithServer({required String url, required String username, required String password}) async {
    final base = url.trim();
    if (!isAllowedServerUrl(base)) return (error: tr('Địa chỉ máy chủ phải bắt đầu bằng https://'), vaultMismatch: false);
    final name = AccountPolicy.normalizeUsername(username);
    if (name == null) return (error: tr('Tên đăng nhập hoặc mật khẩu không đúng'), vaultMismatch: false);
    busy = true;
    error = null;
    notifyListeners();
    try {
      final s = await _cfLogin(base, name, password);
      final blob = await CloudflareSync(_cfApi, s).fetch();
      if (blob == null) {
        // Tài khoản có nhưng chưa có kho (lần tạo trước dở dang): tạo kho mới bằng mật khẩu này.
        return (error: await _createVaultForAccount(base, name, password, s), vaultMismatch: false);
      }
      final VaultSession session;
      try {
        session = await isoOpenPassphrase(blob.bytes, password);
      } on AuthenticationFailedException {
        await _cfApi.logout(s);
        return (error: tr('Đăng nhập được, nhưng mật khẩu này không mở được kho. Kho có thể đang dùng mật khẩu khác.'), vaultMismatch: true);
      } on VaultException catch (e) {
        await _cfApi.logout(s);
        return (error: tr('Không mở được kho: {p0}', {'p0': e.message}), vaultMismatch: false);
      }
      await _adoptDownloadedVault(base, name, s, blob, session);
      await _remember();
      return (error: null, vaultMismatch: false);
    } on CloudflareApiException catch (e) {
      return (error: _apiText(e), vaultMismatch: false);
    } on SyncNetworkException catch (e) {
      return (error: tr('Không kết nối được máy chủ ({p0}).', {'p0': e.message}), vaultMismatch: false);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Dùng kho vừa tải từ máy chủ làm kho trên máy này và vào app.
  Future<void> _adoptDownloadedVault(String base, String username, CloudflareSession s, RemoteBlob blob, VaultSession session) async {
    _session = session;
    await VaultStorage.writeAtomic(_file, blob.bytes);
    _saveCfSession(s);
    await _updateSettings(() => _syncConfig = {'type': 'cloudflare', 'url': base, 'username': s.username.isEmpty ? username : s.username});
    provider = CloudflareSync(_cfApi, s, onSession: _saveCfSession);
    syncStatus = SyncStatus.idle;
    _syncState = SyncState(baseBytes: blob.bytes, remoteVersion: blob.version);
    await _saveSyncState();
    data = VaultData.fromJson(session.payload);
    noPassword = false;
    phase = Phase.unlocked;
    _scheduleNotifications();
  }

  Future<List<CloudflareDevice>> cloudflareDevices() => _cfApi.devices(cfSession!);

  Future<void> revokeCloudflareDevice(String id) => _cfApi.revokeDevice(cfSession!, id);

  Future<void> signOutCloudflare() async {
    final s = cfSession;
    if (s != null) {
      try {
        await _cfApi.logout(s);
      } on Object {
        // Không có mạng thì vẫn đăng xuất cục bộ.
      }
    }
    try {
      await _secure.delete(key: _cfKey);
    } on Object {
      // bỏ qua
    }
    cfSession = null;
    await disableSync();
  }

  /// Máy mới: đăng nhập tài khoản rồi tải kho có sẵn về, mở bằng passphrase hoặc mã khôi phục của KHO (không phải mật khẩu tài khoản).
  Future<String?> joinFromCloud({
    required String url,
    required String username,
    required String accountPassword,
    String? vaultPassphrase,
    String? recoveryKey,
  }) async {
    final base = url.trim();
    if (!isAllowedServerUrl(base)) return tr('Địa chỉ máy chủ phải bắt đầu bằng https://');
    busy = true;
    notifyListeners();
    try {
      final name = AccountPolicy.normalizeUsername(username);
      if (name == null) return tr('Tên đăng nhập hoặc mật khẩu không đúng');
      final s = await _cfLogin(base, name, accountPassword);
      final blob = await CloudflareSync(_cfApi, s).fetch();
      if (blob == null) {
        await _cfApi.logout(s);
        return tr('Tài khoản này chưa có kho trên máy chủ. Hãy tạo kho ở máy đầu tiên rồi bật đồng bộ.');
      }
      final bytes = blob.bytes;
      final VaultSession session;
      try {
        if (recoveryKey != null) {
          final rk = RecoveryKey.parse(recoveryKey);
          session = await isoOpenRecovery(bytes, rk);
        } else {
          session = await isoOpenPassphrase(bytes, vaultPassphrase ?? '');
        }
      } on AuthenticationFailedException {
        await _cfApi.logout(s);
        return tr('Sai mật khẩu kho hoặc mã khôi phục (đây là mật khẩu của KHO, khác mật khẩu tài khoản).');
      } on VaultException catch (e) {
        await _cfApi.logout(s);
        return tr('Không mở được kho: {p0}', {'p0': e.message});
      }
      await _adoptDownloadedVault(base, name, s, blob, session);
      await _remember();
      return null;
    } on CloudflareApiException catch (e) {
      return _apiText(e);
    } on SyncNetworkException catch (e) {
      return tr('Không kết nối được máy chủ ({p0}).', {'p0': e.message});
    } on InvalidInputException {
      return tr('Mã khôi phục không đúng định dạng');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---- Google Drive ----

  String _driveError(Object e) => switch (e) {
        SyncAuthException() => e.message,
        SyncNetworkException() => tr('Không kết nối được Google Drive ({p0}).', {'p0': e.message}),
        _ => tr('Lỗi Google Drive: {p0}', {'p0': e}),
      };

  /// Màn đầu: đăng nhập Google rồi xem Drive đã có kho chưa. `hasVault` = true thì phải MỞ kho (cần mật khẩu của kho),
  /// ngược lại thì TẠO kho mới.
  Future<({String? error, bool hasVault})> driveSignIn() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final auth = driveAuthFactory();
      final err = await auth.signIn();
      if (err != null) return (error: err, hasVault: false);
      final blob = await DriveSync(auth, base: driveBase).fetch();
      _pendingDriveAuth = auth;
      return (error: null, hasVault: blob != null);
    } on Object catch (e) {
      return (error: _driveError(e), hasVault: false);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _useDrive(DriveAccountAuth auth) async {
    _driveAuth = auth;
    _pendingDriveAuth = null;
    await _updateSettings(() => _syncConfig = {'type': 'drive', 'account': auth.email ?? ''});
    provider = DriveSync(auth, base: driveBase);
    syncStatus = SyncStatus.idle;
  }

  /// Drive chưa có kho: tạo kho mới bằng [password], bật đồng bộ Drive. Sau đó người dùng lưu mã khôi phục rồi vào app.
  Future<String?> driveCreateVault(String password) async {
    final auth = _pendingDriveAuth;
    if (auth == null) return tr('Hãy đăng nhập Google trước.');
    final weak = newPasswordError(password);
    if (weak != null) return weak;
    busy = true;
    error = null;
    notifyListeners();
    try {
      // Kiểm tra lại: nếu máy khác vừa tạo kho trên Drive này thì không tạo đè, phải mở kho đó.
      if (await DriveSync(auth, base: driveBase).fetch() != null) {
        _pendingDriveAuth = null;
        return tr('Google Drive này vừa có kho (tạo ở máy khác). Hãy quay lại và đăng nhập Google lại để mở kho đó.');
      }
      final (session, recovery) = await isoCreateCalibrated(password);
      session.payload = const VaultData().toJson();
      _session = session;
      await _writeNow();
      await _useDrive(auth);
      _syncState = const SyncState();
      await _remember();
      pendingRecovery = recovery.formatted;
      return null;
    } on Object catch (e) {
      return tr('Không tạo được kho: {p0}', {'p0': e});
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Drive đã có kho (tạo ở máy khác): mở bằng mật khẩu của kho rồi vào app.
  Future<String?> driveOpenVault(String password) async {
    final auth = _pendingDriveAuth;
    if (auth == null) return tr('Hãy đăng nhập Google trước.');
    busy = true;
    error = null;
    notifyListeners();
    try {
      final blob = await DriveSync(auth, base: driveBase).fetch();
      if (blob == null) return tr('Không thấy kho trên Google Drive.');
      final VaultSession session;
      try {
        session = await isoOpenPassphrase(blob.bytes, password);
      } on AuthenticationFailedException {
        return tr('Sai mật khẩu kho.');
      } on VaultException catch (e) {
        return tr('Không mở được kho: {p0}', {'p0': e.message});
      }
      _session = session;
      await VaultStorage.writeAtomic(_file, blob.bytes);
      await _useDrive(auth);
      _syncState = SyncState(baseBytes: blob.bytes, remoteVersion: blob.version);
      await _saveSyncState();
      data = VaultData.fromJson(session.payload);
      noPassword = false;
      phase = Phase.unlocked;
      _scheduleNotifications();
      await _remember();
      return null;
    } on Object catch (e) {
      return _driveError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Cài đặt: bật đồng bộ Google Drive cho kho đang có trên máy. Từ chối nếu Drive đã có một kho KHÁC (khóa khác).
  Future<String?> enableDriveSync() async {
    final s = _session;
    if (s == null) return tr('Hãy mở khóa kho trước.');
    busy = true;
    notifyListeners();
    try {
      final auth = driveAuthFactory();
      final err = await auth.signIn();
      if (err != null) return err;
      final blob = await DriveSync(auth, base: driveBase).fetch();
      if (blob != null) {
        try {
          await s.decryptRemote(blob.bytes);
        } on AuthenticationFailedException {
          await auth.signOut();
          return tr('Google Drive này đã có một kho khác (khóa khác). Để dùng kho đó, hãy cài lại app và chọn đăng nhập Google ở màn đầu.');
        }
      }
      await _useDrive(auth);
      _syncState = const SyncState();
      notifyListeners();
      unawaited(syncNow());
      return null;
    } on Object catch (e) {
      return _driveError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String get syncLabel => switch (_syncConfig?['type']) {
        'folder' => 'Thư mục: ${_syncConfig!['path']}',
        'cloudflare' => 'Cloudflare: ${_syncConfig!['username'] ?? _syncConfig!['email']}',
        'drive' => 'Google Drive: ${_syncConfig!['account'] ?? ''}',
        _ => tr('Chưa bật'),
      };

  Future<void> _loadSyncState() async {
    try {
      if (!await _syncStateFile.exists()) return;
      final j = jsonDecode(await _syncStateFile.readAsString()) as Map<String, dynamic>;
      final b = j['base'];
      _syncState = SyncState(baseBytes: b is String ? base64Decode(b) : null, remoteVersion: j['version'] as String?);
      final t = j['lastSync'];
      if (t is String) lastSync = DateTime.tryParse(t);
    } on Object {
      _syncState = const SyncState();
    }
  }

  Future<void> _saveSyncState() async {
    try {
      await _syncStateFile.writeAsString(
        jsonEncode({
          if (_syncState.baseBytes != null) 'base': base64Encode(_syncState.baseBytes!),
          'version': _syncState.remoteVersion,
          if (lastSync != null) 'lastSync': lastSync!.toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } on Object {
      // Mất trạng thái chỉ khiến lần sau gộp không có gốc, không mất dữ liệu.
    }
  }

  Future<void> setFolderSync(String path) async {
    await _updateSettings(() => _syncConfig = {'type': 'folder', 'path': path});
    _applySyncConfig();
    _syncState = const SyncState();
    notifyListeners();
    await syncNow();
  }

  Future<void> disableSync() async {
    _syncTimer?.cancel();
    final drive = _driveAuth;
    if (drive != null) {
      _driveAuth = null;
      await drive.signOut();
    }
    await _updateSettings(() => _syncConfig = null);
    _applySyncConfig();
    _syncState = const SyncState();
    conflicts = [];
    syncError = null;
    try {
      if (await _syncStateFile.exists()) await _syncStateFile.delete();
    } on Object {
      // bỏ qua
    }
    notifyListeners();
  }

  void _scheduleSync() {
    if (provider == null) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(Timing.syncDebounce, () => unawaited(syncNow()));
  }

  /// Đồng bộ ngay. An toàn khi gọi nhiều lần: lần đang chạy thì bỏ qua.
  Future<void> syncNow() async {
    final p = provider;
    final s = _session;
    if (p == null || s == null || phase != Phase.unlocked || syncStatus == SyncStatus.syncing) return;
    syncStatus = SyncStatus.syncing;
    syncError = null;
    notifyListeners();
    final snapshot = data;
    var editedDuringSync = false;
    try {
      final out = await SyncService(p).sync(session: s, local: snapshot, state: _syncState);
      var merged = out.data;
      if (!identical(data, snapshot)) {
        // Người dùng sửa trong lúc đang đồng bộ: gộp ba chiều (gốc = bản lúc bắt đầu) để không ghi đè mất phần vừa sửa.
        editedDuringSync = true;
        merged = mergeVaults(local: data, remote: out.data, base: snapshot).merged;
      }
      data = merged;
      s.payload = data.toJson();
      _syncState = out.state;
      conflicts = out.conflicts;
      lastSync = DateTime.now();
      await _writeNow();
      await _saveSyncState();
      syncStatus = SyncStatus.idle;
    } on SyncNetworkException catch (e) {
      syncStatus = SyncStatus.error;
      syncError = tr('Không kết nối được nơi đồng bộ ({p0}). Dữ liệu trên máy vẫn an toàn, sẽ thử lại sau.', {'p0': e.message});
    } on SyncAuthException catch (e) {
      syncStatus = SyncStatus.error;
      syncError = tr('Cần đăng nhập lại: {p0}', {'p0': e.message});
    } on AuthenticationFailedException {
      syncStatus = SyncStatus.error;
      syncError = tr('Bản trên nơi đồng bộ dùng khóa khác (đã đổi mật khẩu hoặc xoay khóa ở máy khác). Hãy khóa rồi mở lại bằng mật khẩu mới.');
    } on VaultException catch (e) {
      syncStatus = SyncStatus.error;
      syncError = tr('Không đồng bộ được: {p0}', {'p0': e.message});
    } finally {
      notifyListeners();
      if (editedDuringSync) _scheduleSync(); // bản vừa sửa chưa lên nơi đồng bộ: hẹn đồng bộ lại
    }
  }

  /// Chọn bản cho một mục xung đột.
  void resolveConflictChoice(ItemConflict c, ConflictChoice choice) {
    upsert(resolveConflict(c, choice, clock: clock));
    conflicts = [for (final x in conflicts) if (x.id != c.id) x];
    notifyListeners();
  }

  // ---- Tự khóa khi ra nền ----

  Future<void> setLockAfter(int seconds) async {
    // Bỏ "Không tự khóa" thì xóa mật khẩu đã ghi nhớ: lần mở app sau phải nhập lại.
    if (seconds != LockPolicy.never) await _forget();
    await _updateSettings(() => lockAfterSeconds = seconds);
  }
  Future<void> setTheme(String mode) => _updateSettings(() => themeMode = mode);
  Future<void> setLanguage(String lang) => _updateSettings(() => language = lang);
  Future<void> setAccent(int i) => _updateSettings(() => accent = i);
  Future<void> setGroupBy(GroupBy g) => _updateSettings(() => groupBy = g);
  Future<void> setSortBy(SortBy s) => _updateSettings(() => sortBy = s);
  /// Ghi nhớ loại mục vừa tạo (không báo giao diện dựng lại).
  void rememberType(ItemType t) {
    if (t == lastType) return;
    lastType = t;
    unawaited(_updateSettings(() {}));
  }

  Future<void> setShowLogos(bool on) async {
    BrandConfig.enabled = on;
    await _updateSettings(() => showLogos = on);
  }

  Future<void> setBlockScreenshots(bool on) async {
    await _updateSettings(() => blockScreenshots = on);
    await PlatformBridge.setSecure(on: on);
  }

  Future<void> _updateSettings(void Function() change) async {
    change();
    notifyListeners();
    try {
      await _settingsFile.writeAsString(
        jsonEncode({
          SettingsKey.lockAfter: lockAfterSeconds,
          SettingsKey.theme: themeMode,
          SettingsKey.language: language,
          SettingsKey.accent: accent,
          SettingsKey.groupBy: groupBy.name,
          SettingsKey.sortBy: sortBy.name,
          SettingsKey.blockScreenshots: blockScreenshots,
          SettingsKey.showLogos: showLogos,
          SettingsKey.lastType: lastType.name,
          SettingsKey.snooze: {for (final e in snoozed.entries) e.key: e.value.toUtc().toIso8601String()},
          SettingsKey.dismissedServices: dismissedServices.toList(),
          if (_syncConfig != null) SettingsKey.sync: _syncConfig,
        }),
        flush: true,
      );
    } on Object {
      // Không lưu được cài đặt thì vẫn dùng được trong phiên này.
    }
  }

  /// Bọc các thao tác mở app ngoài (chọn file, camera) để không bị tự khóa giữa chừng.
  Future<T> external<T>(Future<T> Function() f) async {
    _external = true;
    try {
      return await f();
    } finally {
      _external = false;
      _pausedAt = null;
    }
  }

  void onBackground() {
    if (phase != Phase.unlocked || _external || noPassword || lockAfterSeconds == LockPolicy.never) return;
    if (lockAfterSeconds == 0) {
      unawaited(lock());
    } else {
      _pausedAt ??= DateTime.now();
    }
  }

  void onForeground() {
    unawaited(syncNow());
    final p = _pausedAt;
    _pausedAt = null;
    if (p != null && phase == Phase.unlocked && DateTime.now().difference(p).inSeconds >= lockAfterSeconds) {
      unawaited(lock());
    }
  }

  /// Bản sao lưu đã mã hóa (chính là file kho).
  Future<Uint8List> backupBytes() async {
    await _writeNow();
    return _file.readAsBytes();
  }

  // ---- Sửa dữ liệu ----

  void mutate(VaultData Function(VaultData) change) {
    data = change(data);
    _session?.payload = data.toJson();
    notifyListeners();
    if (_session == null) return; // chưa có phiên (test): không có gì để lưu
    _saveTimer?.cancel();
    _saveTimer = Timer(Timing.saveDebounce, () => unawaited(_writeNow()));
    _scheduleSync();
    _scheduleNotifications();
  }

  void upsert(Item item) => mutate((d) => d.upsert(item));
  void trash(Item i) => upsert(i.moveToTrash(clock: clock));
  void restore(Item i) => upsert(i.restore(clock: clock));
  void purge(Item i) => mutate((d) => d.purge(i.id, clock: clock));

  /// Xóa vĩnh viễn mọi mục trong thùng rác.
  void emptyTrash() => mutate((d) {
        var out = d;
        for (final i in d.items.where((i) => i.inTrash)) {
          out = out.purge(i.id, clock: clock);
        }
        return out;
      });
  /// Thêm bộ dữ liệu mẫu (giả) để xem giao diện. Trả về số mục đã thêm.
  int addDemoData() {
    final items = buildDemoItems(clock);
    mutate((d) {
      var out = d;
      for (final i in items) {
        out = out.upsert(i);
      }
      return out;
    });
    return items.length;
  }

  /// Dấu nhận dạng mục mẫu: loại, tên và các trường (bỏ trường ngày hết hạn vì nó tính theo ngày nạp).
  static String _demoSig(Item i) =>
      '${i.type.name}|${i.title}|${i.fields.where((f) => f.key != 'expiry').map((f) => '${f.key}=${f.label}=${f.value}').join(';')}';

  /// Các mục mẫu còn nguyên như lúc nạp (kể cả trong thùng rác). Mục mẫu đã bị sửa thì coi là của người dùng, không tính.
  List<Item> get demoItems {
    final sigs = buildDemoItems(HlcClock(node: 'demo')).map(_demoSig).toSet();
    return data.items.where((i) => sigs.contains(_demoSig(i))).toList();
  }

  /// Xóa hẳn các mục mẫu (xóa cả trên máy khác khi đồng bộ). Trả về số mục đã xóa.
  int removeDemoData() {
    final ids = demoItems.map((i) => i.id).toList();
    if (ids.isEmpty) return 0;
    mutate((d) {
      var out = d;
      for (final id in ids) {
        out = out.purge(id, clock: clock);
      }
      return out;
    });
    return ids.length;
  }

  /// Các nhóm đang có (từ mục chưa vào thùng rác), sắp theo tên.
  List<String> get groups => data.items.where((i) => !i.inTrash && i.group.isNotEmpty).map((i) => i.group).toSet().toList()..sort();
  int countInGroup(String g) => data.items.where((i) => !i.inTrash && i.group == g).length;

  /// Đổi tên nhóm (kể cả mục trong thùng rác, để khôi phục không mất nhóm). Trùng tên nhóm khác thì gộp vào.
  void renameGroup(String from, String to) {
    final name = to.trim();
    if (name.isEmpty || name == from) return;
    mutate((d) {
      var out = d;
      for (final i in d.items.where((i) => i.group == from)) {
        out = out.upsert(i.edit(clock: clock, group: name));
      }
      return out;
    });
  }

  /// Xóa nhóm: các mục KHÔNG bị xóa, chỉ thành "không nhóm".
  void deleteGroup(String g) {
    mutate((d) {
      var out = d;
      for (final i in d.items.where((i) => i.group == g)) {
        out = out.upsert(i.edit(clock: clock, group: ''));
      }
      return out;
    });
  }

  void toggleFavorite(Item i) => upsert(i.edit(clock: clock, favorite: !i.favorite));
  /// HOTP: tăng bộ đếm để lấy mã kế tiếp.
  void hotpNext(Item i) {
    final t = i.totp;
    if (t == null || !t.isHotp) return;
    upsert(i.edit(clock: clock, totp: t.copyWith(counter: t.counter + 1)));
  }

  void changePassword(Item i, String newPassword) => upsert(i.changePassword(newPassword, clock: clock));

  /// Chỉ dùng trong test: vào thẳng trạng thái đã mở, không cần đĩa hay mật mã.
  @visibleForTesting
  void debugUnlock([VaultData? initial]) {
    clock = HlcClock(node: 'test');
    data = initial ?? const VaultData();
    phase = Phase.unlocked;
    notifyListeners();
  }

  Future<void> _writeNow() {
    final s = _session;
    if (s == null) return _saving;
    _saving = _saving.then((_) async {
      await VaultStorage.writeAtomic(_file, await s.save());
    });
    return _saving;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
