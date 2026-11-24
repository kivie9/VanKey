import 'dart:typed_data';

import '../errors.dart';
import '../vault/merge.dart';
import '../vault/models.dart';
import '../vault/vault_session.dart';
import 'sync_provider.dart';

/// Trạng thái cần giữ giữa các lần đồng bộ (do tầng app lưu xuống đĩa).
final class SyncState {
  const SyncState({this.baseBytes, this.remoteVersion});

  /// Bản kho (đã mã hóa) ở lần đồng bộ thành công trước: làm gốc cho gộp 3 bên.
  final Uint8List? baseBytes;

  /// Phiên bản của bản trên máy chủ tại lần đó.
  final String? remoteVersion;
}

final class SyncOutcome {
  const SyncOutcome({
    required this.data,
    required this.state,
    required this.conflicts,
    required this.uploaded,
    required this.changedLocal,
  });

  /// Dữ liệu sau gộp (đã đặt vào `session.payload`).
  final VaultData data;
  final SyncState state;

  /// Mục sửa ở cả hai máy. Đã tự chọn bản mới hơn; giao diện có thể cho người dùng đổi.
  final List<ItemConflict> conflicts;
  final bool uploaded;

  /// Có thay đổi từ máy chủ cần lưu xuống máy này.
  final bool changedLocal;
}

/// Đồng bộ: tải → giải mã → gộp 3 bên → mã hóa → tải lên (kiểm tra phiên bản), lặp lại nếu có người ghi chen.
final class SyncService {
  SyncService(this.provider, {this.maxAttempts = 5, this.networkRetries = 3, Future<void> Function(Duration)? delay})
      : _delay = delay ?? Future.delayed;

  final SyncProvider provider;
  final int maxAttempts;
  final int networkRetries;
  final Future<void> Function(Duration) _delay;

  /// Chờ ban đầu giữa các lần thử lại khi mất mạng (nhân đôi sau mỗi lần).
  static const initialRetryWait = Duration(seconds: 1);

  Future<T> _withRetry<T>(Future<T> Function() op) async {
    var wait = initialRetryWait;
    for (var i = 0;; i++) {
      try {
        return await op();
      } on SyncNetworkException {
        if (i >= networkRetries) rethrow;
        await _delay(wait);
        wait *= 2;
      }
    }
  }

  Future<SyncOutcome> sync({required VaultSession session, required VaultData local, SyncState state = const SyncState()}) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final remote = await _withRetry(provider.fetch);

      // Chưa có gì trên máy chủ: tải bản của ta lên.
      if (remote == null) {
        session.payload = local.toJson();
        final bytes = await session.save();
        try {
          final v = await _withRetry(() => provider.upload(bytes));
          return SyncOutcome(data: local, state: SyncState(baseBytes: bytes, remoteVersion: v), conflicts: const [], uploaded: true, changedLocal: false);
        } on SyncConflictException {
          continue; // có người vừa tạo: vòng sau sẽ gộp
        }
      }

      final (remoteHeader, remotePayload) = await session.decryptRemote(remote.bytes);
      final remoteData = VaultData.fromJson(remotePayload);

      VaultData? base;
      final baseBytes = state.baseBytes;
      if (baseBytes != null) {
        try {
          base = VaultData.fromJson((await session.decryptRemote(baseBytes)).$2);
        } on VaultException {
          base = null; // gốc không dùng được (khóa đã xoay...): gộp không có gốc
        }
      }

      final r = mergeVaults(local: local, remote: remoteData, base: base);
      final slotsNewerLocally = session.slotsRev > remoteHeader.slotsRev;
      session.adoptSlotsFrom(remoteHeader);

      if (!r.changesRemote && !slotsNewerLocally) {
        session.payload = r.merged.toJson();
        return SyncOutcome(
          data: r.merged,
          state: SyncState(baseBytes: remote.bytes, remoteVersion: remote.version),
          conflicts: r.conflicts,
          uploaded: false,
          changedLocal: r.changesLocal,
        );
      }

      session.payload = r.merged.toJson();
      final bytes = await session.save();
      try {
        final v = await _withRetry(() => provider.upload(bytes, ifMatch: remote.version));
        return SyncOutcome(
          data: r.merged,
          state: SyncState(baseBytes: bytes, remoteVersion: v),
          conflicts: r.conflicts,
          uploaded: true,
          changedLocal: r.changesLocal,
        );
      } on SyncConflictException {
        local = r.merged; // giữ phần đã gộp rồi thử lại với bản máy chủ mới
        continue;
      }
    }
    throw const SyncNetworkException('không đồng bộ được sau nhiều lần thử (máy khác liên tục ghi)');
  }
}
