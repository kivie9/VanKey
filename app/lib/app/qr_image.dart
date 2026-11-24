import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Đọc mã QR từ ảnh (PNG, JPEG, ...) bằng Dart thuần, không cần camera. Dùng cho Windows và khi ML Kit không đọc được.
abstract final class QrImageDecoder {
  /// Trả về nội dung mã QR, hoặc `null` nếu không tìm thấy hoặc ảnh không đọc được.
  static String? decode(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    // Ảnh chụp màn hình thường rất lớn: thu nhỏ để bộ đọc chạy nhanh mà vẫn đủ nét.
    final work = image.width > 1600 ? img.copyResize(image, width: 1600) : image;
    final pixels = work.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List();
    final source = RGBLuminanceSource(work.width, work.height, pixels);
    for (final binarizer in <BinaryBitmap Function()>[
      () => BinaryBitmap(HybridBinarizer(source)),
      () => BinaryBitmap(GlobalHistogramBinarizer(source)),
    ]) {
      try {
        return QRCodeReader().decode(binarizer()).text;
      } on Object {
        // thử cách nhị phân hóa kế tiếp
      }
    }
    return null;
  }

  /// Dựng ảnh PNG chứa mã QR (dùng trong test và để xuất mã).
  static Uint8List encodePng(String text, {int scale = 6, int quiet = 4}) {
    final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
    final size = (matrix.width + quiet * 2) * scale;
    final image = img.Image(width: size, height: size);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) == 1) {
          img.fillRect(
            image,
            x1: (x + quiet) * scale,
            y1: (y + quiet) * scale,
            x2: (x + quiet + 1) * scale - 1,
            y2: (y + quiet + 1) * scale - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }
}
