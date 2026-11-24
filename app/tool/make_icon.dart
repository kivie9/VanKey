// Tạo biểu tượng VanKey (hình chìa khóa) bằng mã, để mọi kích thước ra từ một nguồn duy nhất.
import 'dart:typed_data';
//   dart run tool/make_icon.dart
// Ghi: biểu tượng Android (cổ điển + adaptive), bản 512 px và .ico trong docs/branding.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

const _top = (0x5B, 0x77, 0xF2);
const _bottom = (0x3A, 0x4F, 0xC4);
const _bg = '#4F6BED';

/// Chìa khóa trắng, vẽ trên ảnh vuông [size] với phần chìa chiếm [fill] cạnh (0..1).
void _drawKey(img.Image im, {required double fill}) {
  final s = im.width.toDouble();
  final white = img.ColorRgba8(255, 255, 255, 255);
  final span = s * fill;
  final x0 = (s - span) / 2; // lề trái của chìa
  final cy = s / 2;
  final ringR = span * 0.24;
  final cx = x0 + ringR;
  final shaftH = span * 0.17;
  final shaftX1 = (cx + ringR * 0.55).round();
  final shaftX2 = (x0 + span).round();

  // Thân chìa và hai răng.
  img.fillRect(im, x1: shaftX1, y1: (cy - shaftH / 2).round(), x2: shaftX2, y2: (cy + shaftH / 2).round(), color: white, radius: shaftH / 2);
  final toothW = span * 0.1;
  final toothH = span * 0.2;
  for (final k in [0.0, 1.75]) {
    final tx = (shaftX2 - toothW * 1.15 - k * toothW).round();
    img.fillRect(im, x1: tx, y1: (cy).round(), x2: (tx + toothW).round(), y2: (cy + toothH).round(), color: white, radius: toothW * 0.25);
  }
  // Vòng tròn đầu chìa có lỗ.
  img.fillCircle(im, x: cx.round(), y: cy.round(), radius: ringR.round(), color: white);
  // Khoét lỗ: đặt thẳng alpha 0 (fillCircle với màu trong suốt chỉ hòa trộn chứ không xóa).
  final hr = ringR * 0.42;
  for (var y = (cy - hr).floor(); y <= (cy + hr).ceil(); y++) {
    for (var x = (cx - hr).floor(); x <= (cx + hr).ceil(); x++) {
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= hr * hr) im.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
}

img.Image _gradientSquare(int size, {double cornerRatio = 0}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    final t = y / (size - 1);
    final r = (_top.$1 + (_bottom.$1 - _top.$1) * t).round();
    final g = (_top.$2 + (_bottom.$2 - _top.$2) * t).round();
    final b = (_top.$3 + (_bottom.$3 - _top.$3) * t).round();
    for (var x = 0; x < size; x++) {
      im.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  if (cornerRatio > 0) {
    // Bo góc: xóa phần ngoài hình vuông bo (tô alpha 0 bằng mặt nạ).
    final mask = img.Image(width: size, height: size, numChannels: 4);
    img.fillRect(mask, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: img.ColorRgba8(255, 255, 255, 255), radius: size * cornerRatio);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (mask.getPixel(x, y).a == 0) im.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return im;
}

Uint8List _png(img.Image im) => Uint8List.fromList(img.encodePng(im));

void _write(String path, List<int> bytes) {
  final f = File(path)..createSync(recursive: true);
  f.writeAsBytesSync(bytes);
  print('  $path');
}

void main() {
  const master = 1024;

  // Biểu tượng cổ điển: nền chuyển màu, bo góc, chìa khóa lớn.
  final legacy = _gradientSquare(master, cornerRatio: 0.22);
  final keyLayer = img.Image(width: master, height: master, numChannels: 4);
  _drawKey(keyLayer, fill: 0.62);
  img.compositeImage(legacy, keyLayer);

  // Lớp trước của adaptive: chỉ chìa khóa trong vùng an toàn (≈ 54% khung).
  final fg = img.Image(width: master, height: master, numChannels: 4);
  _drawKey(fg, fill: 0.46);

  final res = 'android/app/src/main/res';
  const legacySizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  const fgSizes = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};
  print('Android:');
  legacySizes.forEach((d, px) => _write('$res/mipmap-$d/ic_launcher.png', _png(img.copyResize(legacy, width: px, height: px, interpolation: img.Interpolation.cubic))));
  fgSizes.forEach((d, px) => _write('$res/mipmap-$d/ic_launcher_foreground.png', _png(img.copyResize(fg, width: px, height: px, interpolation: img.Interpolation.cubic))));

  _write('$res/mipmap-anydpi-v26/ic_launcher.xml', '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''.codeUnits);
  _write('$res/values/ic_launcher_colors.xml', '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$_bg</color>
</resources>
'''.codeUnits);

  print('Thương hiệu:');
  _write('../docs/branding/vankey-icon-1024.png', _png(legacy));
  _write('../docs/branding/vankey-icon-512.png', _png(img.copyResize(legacy, width: 512, height: 512, interpolation: img.Interpolation.cubic)));
  final ico = img.Image(width: 256, height: 256, numChannels: 4);
  img.compositeImage(ico, img.copyResize(legacy, width: 256, height: 256, interpolation: img.Interpolation.cubic));
  _write('../docs/branding/vankey.ico', img.encodeIco(ico));
  print('Xong.');
}
