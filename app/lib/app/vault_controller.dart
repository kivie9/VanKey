import 'demo_data.dart';
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
import '../core/vault/merge.dart';
import '../core/vault/hlc.dart';
import '../core/vault/models.dart';
import '../core/vault/vault_session.dart';
import '../core/vault/vault_storage.dart';
import 'notification_service.dart';
import 'brand.dart';
import 'isolate_ops.dart';
import 'platform_bridge.dart';
import 'theme.dart' show accentColors;
import './i18n.dart';

enum Phase { loading, onboarding, locked, unlocked }

enum GroupBy { group, type, none }

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
  int lockAfterSeconds = 60;
  String themeMode = 'system'; // system | light | dark
  String language = 'system'; // system | vi | en
  int accent = 0;
  GroupBy groupBy = GroupBy.group;
  SortBy sortBy = SortBy.name;
  bool blockScreenshots = true;
  bool showLogos = true;
  ItemType lastType = ItemType.login; // loại mục vừa tạo gần nhất: lần sau chọn sẵn
  Map<String, DateTime> snoozed = {};

  // Làm chậm khi nhập sai mật khẩu liên tiếp (chỉ chặn giao diện; không thay thế độ khó của Argon2id).
  int _failures = 0;
  DateTime? _blockedUntil;
  bool biometricEnabled = false;
  static const _bioKey = 'vault.bio.passphrase';
  final _localAuth = LocalAuthentication();
  DateTime? _pausedAt;
  bool _external = false;

  /// Chế độ không mật khẩu: khóa kho nằm trong kho khóa của hệ điều hành (Android Keystore), app tự mở.
  bool noPassword = false;

  static const _secure = FlutterSecureStorage();
  static const _secretKey = 'vault.device.secret';
  // Bí mật ngẫu nhiên 256 bit nên không cần Argon2 nặng.
  static const _quickParams = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);

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
    _settingsFile = File('${dir.path}${Platform.pathSeparator}settings.json');
    try {
      if (await _settingsFile.exists()) {
        final j = jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>;
        final v = j['lockAfter'];
        if (v is int && v >= 0 && v <= 3600) lockAfterSeconds = v;
        final lg = j['language'];
        if (lg == 'vi' || lg == 'en' || lg == 'system') language = lg as String;
        final t = j['theme'];
        if (t == 'light' || t == 'dark' || t == 'system') themeMode = t as String;
        final a = j['accent'];
        if (a is int && a >= 0 && a < accentColors.length) accent = a;
        final sc = j['sync'];
        if (sc is Map<String, dynamic>) _syncConfig = sc;
        final sn = j['snooze'];
        if (sn is Map<String, dynamic>) {
          snoozed = {for (final e in sn.entries) if (e.value is String && DateTime.tryParse(e.value as String) != null) e.key: DateTime.parse(e.value as String)};
        }
        final so = j['sortBy'];
        if (so is String) sortBy = SortBy.values.firstWhere((e) => e.name == so, orElse: () => SortBy.name);
        final lt = j['lastType'];
        if (lt is String) lastType = ItemType.fromName(lt);
        if (j['showLogos'] is bool) showLogos = j['showLogos'] as bool;
        BrandConfig.enabled = showLogos;
        if (j['blockScreenshots'] is bool) blockScreenshots = j['blockScreenshots'] as bool;
        final g = j['groupBy'];
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

  /// Dùng ngay, không cần mật khẩu (có thể đặt mật khẩu sau trong Cài đặt).
  Future<void> createQuick() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final secret = base64Url.encode(Csprng().bytes(32));
      await _secure.write(key: _secretKey, value: secret);
      final (session, _) = await isoCreateWith(secret, _quickParams);
      session.payload = const VaultData().toJson();
      _session = session;
      await _writeNow();
      data = VaultData.fromJson(session.payload);
      noPassword = true;
      phase = Phase.unlocked;
    } on Object catch (e) {
      await _deleteSecret();
      error = tr('Không tạo được kho: {p0}', {'p0': e});
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Chuyển sang chế độ có mật khẩu.
  Future<void> setPassword(String passphrase) async {
    final s = _session!;
    final updated = await isoRewrap(s, passphrase, Argon2Params.standard);
    s.close();
    _session = updated;
    await _writeNow();
    await _deleteSecret();
    await disableBiometric();
    noPassword = false;
    notifyListeners();
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
  Future<String?> changeVaultPassword(String current, String next) async {
    if (!await verifyPassphrase(current)) return tr('Mật khẩu hiện tại không đúng');
    await setPassword(next);
    return null;
  }

  /// Tắt mật khẩu: kho chuyển sang khóa ngẫu nhiên giữ trong Keystore, app tự mở.
  Future<String?> removePassword(String current) async {
    if (!await verifyPassphrase(current)) return tr('Mật khẩu hiện tại không đúng');
    final secret = base64Url.encode(Csprng().bytes(32));
    await _secure.write(key: _secretKey, value: secret);
    final s = _session!;
    final updated = await isoRewrap(s, secret, _quickParams);
    s.close();
    _session = updated;
    await _writeNow();
    await disableBiometric();
    noPassword = true;
    notifyListeners();
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
  }

  Future<bool> unlockWithPassphrase(String passphrase) =>
      _unlock((bytes) => isoOpenPassphrase(bytes, passphrase));

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
      _failures = 0;
      _blockedUntil = null;
      return true;
    } on AuthenticationFailedException {
      error = tr('Sai mật khẩu, hoặc file kho đã bị sửa');
      if (trackFailures && ++_failures >= 3) {
        final secs = (5 * (1 << (_failures - 3).clamp(0, 6))).clamp(5, 300);
        _blockedUntil = DateTime.now().add(Duration(seconds: secs));
        error = tr('Sai mật khẩu. Chờ {p0} giây trước khi thử lại.', {'p0': secs});
      }
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

  // ---- Nhắc nhở ----

  Future<void> snooze(String key, int days) =>
      _updateSettings(() => snoozed = {...snoozed, key: DateTime.now().add(Duration(days: days))});

  Timer? _notifyTimer;

  void _scheduleNotifications() {
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await NotificationService.instance.reschedule(data.items.where((i) => !i.inTrash));
      } on Object {
        // Không đặt được lịch thì thôi, không ảnh hưởng dữ liệu.
      }
    });
  }

  // ---- Vân tay ----

  Future<String?> _readBio() async {
    try {
      return await _secure.read(key: _bioKey);
    } on Object {
      return null;
    }
  }

  Future<bool> biometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  /// Bật mở khóa bằng vân tay: xác minh mật khẩu hiện tại rồi cất vào kho khóa của hệ điều hành.
  /// Lưu ý: mật khẩu nằm trong Keystore, còn vân tay chỉ là lớp chặn của app (chưa gắn khóa với sinh trắc).
  Future<String?> enableBiometric(String passphrase) async {
    final bytes = await VaultStorage.read(_file);
    if (bytes == null) return tr('Không thấy file kho');
    try {
      final probe = await isoOpenPassphrase(bytes, passphrase);
      probe.close();
    } on AuthenticationFailedException {
      return tr('Mật khẩu không đúng');
    }
    try {
      final ok = await external(() => _localAuth.authenticate(localizedReason: tr('Xác nhận để bật mở khóa bằng vân tay'), biometricOnly: true));
      if (!ok) return tr('Chưa xác thực được vân tay');
      await _secure.write(key: _bioKey, value: passphrase);
    } on Object catch (e) {
      return tr('Không bật được: {p0}', {'p0': e});
    }
    biometricEnabled = true;
    notifyListeners();
    return null;
  }

  Future<void> disableBiometric() async {
    try {
      await _secure.delete(key: _bioKey);
    } on Object {
      // bỏ qua
    }
    biometricEnabled = false;
    notifyListeners();
  }

  Future<bool> unlockWithBiometric() async {
    final pass = await _readBio();
    if (pass == null) return false;
    try {
      final ok = await external(() => _localAuth.authenticate(localizedReason: tr('Mở khóa VanKey'), biometricOnly: true));
      if (!ok) return false;
    } on Object {
      return false;
    }
    final opened = await _unlock((b) => isoOpenPassphrase(b, pass), trackFailures: false);
    if (!opened) await disableBiometric(); // mật khẩu đã đổi: bỏ vân tay cũ
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
    if (u.scheme == 'https') return true;
    return u.scheme == 'http' && (u.host == 'localhost' || u.host == '127.0.0.1' || u.host == '10.0.2.2');
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
  Future<String?> signInCloudflare({required String url, required String email, required String password, required bool register}) async {
    final base = url.trim();
    if (!isAllowedServerUrl(base)) return tr('Địa chỉ máy chủ phải bắt đầu bằng https://');
    try {
      final authKey = await isoAuthKey(email, password);
      final s = register ? await _cfApi.register(base, email, authKey, _deviceName) : await _cfApi.login(base, email, authKey, _deviceName);
      _saveCfSession(s);
      await _updateSettings(() => _syncConfig = {'type': 'cloudflare', 'url': base, 'email': s.email.isEmpty ? email : s.email});
      provider = CloudflareSync(_cfApi, s, onSession: _saveCfSession);
      syncStatus = SyncStatus.idle;
      _syncState = const SyncState();
      notifyListeners();
      unawaited(syncNow());
      return null;
    } on CloudflareApiException catch (e) {
      return e.retryAfter != null ? tr('{p0} (chờ {p1} giây)', {'p0': e.message, 'p1': e.retryAfter!}) : e.message;
    } on SyncNetworkException catch (e) {
      return tr('Không kết nối được máy chủ ({p0}).', {'p0': e.message});
    }
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
    required String email,
    required String accountPassword,
    String? vaultPassphrase,
    String? recoveryKey,
  }) async {
    final base = url.trim();
    if (!isAllowedServerUrl(base)) return tr('Địa chỉ máy chủ phải bắt đầu bằng https://');
    busy = true;
    notifyListeners();
    try {
      final authKey = await isoAuthKey(email, accountPassword);
      final s = await _cfApi.login(base, email, authKey, _deviceName);
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
      _session = session;
      await VaultStorage.writeAtomic(_file, bytes);
      _saveCfSession(s);
      await _updateSettings(() => _syncConfig = {'type': 'cloudflare', 'url': base, 'email': s.email.isEmpty ? email : s.email});
      provider = CloudflareSync(_cfApi, s, onSession: _saveCfSession);
      syncStatus = SyncStatus.idle;
      _syncState = SyncState(baseBytes: bytes, remoteVersion: blob.version);
      await _saveSyncState();
      data = VaultData.fromJson(session.payload);
      noPassword = false;
      phase = Phase.unlocked;
      _scheduleNotifications();
      return null;
    } on CloudflareApiException catch (e) {
      return e.message;
    } on SyncNetworkException catch (e) {
      return tr('Không kết nối được máy chủ ({p0}).', {'p0': e.message});
    } on InvalidInputException {
      return tr('Mã khôi phục không đúng định dạng');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String get syncLabel => switch (_syncConfig?['type']) {
        'folder' => 'Thư mục: ${_syncConfig!['path']}',
        'cloudflare' => 'Cloudflare: ${_syncConfig!['email']}',
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
    _syncTimer = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
  }

  /// Đồng bộ ngay. An toàn khi gọi nhiều lần: lần đang chạy thì bỏ qua.
  Future<void> syncNow() async {
    final p = provider;
    final s = _session;
    if (p == null || s == null || phase != Phase.unlocked || syncStatus == SyncStatus.syncing) return;
    syncStatus = SyncStatus.syncing;
    syncError = null;
    notifyListeners();
    try {
      final out = await SyncService(p).sync(session: s, local: data, state: _syncState);
      data = out.data;
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
    }
  }

  /// Chọn bản cho một mục xung đột.
  void resolveConflictChoice(ItemConflict c, ConflictChoice choice) {
    upsert(resolveConflict(c, choice, clock: clock));
    conflicts = [for (final x in conflicts) if (x.id != c.id) x];
    notifyListeners();
  }

  // ---- Tự khóa khi ra nền ----

  Future<void> setLockAfter(int seconds) => _updateSettings(() => lockAfterSeconds = seconds);
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
        jsonEncode({'lockAfter': lockAfterSeconds, 'theme': themeMode, 'language': language, 'accent': accent, 'groupBy': groupBy.name, 'sortBy': sortBy.name, 'blockScreenshots': blockScreenshots, 'showLogos': showLogos, 'lastType': lastType.name, 'snooze': {for (final e in snoozed.entries) e.key: e.value.toUtc().toIso8601String()}, if (_syncConfig != null) 'sync': _syncConfig}),
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
    if (phase != Phase.unlocked || _external || noPassword) return;
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
    _saveTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_writeNow()));
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
