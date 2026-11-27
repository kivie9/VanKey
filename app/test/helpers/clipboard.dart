import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ghi lại mọi lần app chép vào clipboard, theo cả hai đường: chép thường (`Clipboard.setData`) và chép "nhạy cảm"
/// qua kênh `vankey/platform` (Android, Windows; xem platform_bridge.dart).
void mockClipboard(WidgetTester t, void Function(String text) onCopy) {
  final messenger = t.binding.defaultBinaryMessenger;
  const bridge = MethodChannel('vankey/platform');
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') onCopy((call.arguments as Map)['text'] as String);
    return null;
  });
  messenger.setMockMethodCallHandler(bridge, (call) async {
    if (call.method == 'copySensitive') onCopy((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(bridge, null);
  });
}
