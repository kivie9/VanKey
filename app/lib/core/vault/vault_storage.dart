import 'dart:io';
import 'dart:typed_data';

/// Đọc/ghi file kho trên đĩa.
///
/// Ghi **nguyên tử**: ghi ra file tạm cùng thư mục, `flush`, rồi đổi tên đè file cũ; trước đó giữ lại bản trước đó
/// thành `.bak`. Nhờ vậy mất điện hoặc app bị tắt giữa chừng không bao giờ để lại một kho nửa vời.
abstract final class VaultStorage {
  static Future<void> writeAtomic(File target, Uint8List bytes) async {
    final dir = target.parent;
    if (!await dir.exists()) await dir.create(recursive: true);

    final tmp = File('${target.path}.tmp');
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }

    if (await target.exists()) {
      try {
        await target.copy('${target.path}.bak');
      } on FileSystemException {
        // Không giữ được bản dự phòng thì vẫn tiếp tục ghi: bản mới quan trọng hơn bản sao cũ.
      }
    }
    await tmp.rename(target.path);
  }

  /// Nội dung file, hoặc `null` nếu chưa có.
  static Future<Uint8List?> read(File f) async => await f.exists() ? await f.readAsBytes() : null;

  /// Bản dự phòng (lần ghi ngay trước), hoặc `null`.
  static Future<Uint8List?> readBackup(File f) => read(File('${f.path}.bak'));
}
