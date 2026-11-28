import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/screens/home_screen.dart';
import 'app/screens/onboarding_screen.dart';
import 'app/screens/unlock_screen.dart';
import 'app/i18n.dart';
import 'app/theme.dart';
import 'app/vault_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Giới hạn bộ nhớ đệm ảnh (logo thương hiệu, ảnh nền...) để không giữ quá nhiều khi dùng lâu.
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 100;
  cache.maximumSizeBytes = 32 << 20; // 32 MB
  _registerFontLicenses();
  runApp(const VanKeyApp());
}

/// Phông chữ đóng gói trong assets không tự có trong trang giấy phép (chỉ gói pub mới có), nên thêm tay.
void _registerFontLicenses() {
  const fonts = {'Inter': 'OFL-Inter.txt', 'Space Grotesk': 'OFL-SpaceGrotesk.txt', 'JetBrains Mono': 'OFL-JetBrainsMono.txt'};
  LicenseRegistry.addLicense(() async* {
    for (final e in fonts.entries) {
      yield LicenseEntryWithLineBreaks([e.key], await rootBundle.loadString('assets/fonts/${e.value}'));
    }
  });
}

class VanKeyApp extends StatefulWidget {
  const VanKeyApp({super.key});

  @override
  State<VanKeyApp> createState() => _VanKeyAppState();
}

class _VanKeyAppState extends State<VanKeyApp> with WidgetsBindingObserver {
  final _controller = VaultController();
  final _nav = GlobalKey<NavigatorState>();
  Phase _lastPhase = Phase.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.init();
    _controller.addListener(() {
      // Khóa kho thì đóng mọi màn đang mở (chi tiết, sửa...) để không lộ dữ liệu.
      if (_controller.phase == Phase.locked && _lastPhase == Phase.unlocked) {
        _nav.currentState?.popUntil((r) => r.isFirst);
      }
      _lastPhase = _controller.phase;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _controller.onBackground();
      case AppLifecycleState.resumed:
        _controller.onForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          Lang.set(Lang.resolve(_controller.language, WidgetsBinding.instance.platformDispatcher.locale.languageCode));
          return MaterialApp(
          key: ValueKey(Lang.current), // đổi ngôn ngữ thì dựng lại toàn bộ để mọi chữ cập nhật
          navigatorKey: _nav,
          title: 'VanKey',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light, _controller.accent),
          darkTheme: AppTheme.build(Brightness.dark, _controller.accent),
          themeMode: switch (_controller.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          home: switch (_controller.phase) {
            Phase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
            Phase.onboarding => OnboardingScreen(controller: _controller),
            Phase.locked => UnlockScreen(controller: _controller),
            Phase.unlocked => HomeScreen(controller: _controller),
          },
        );
        },
      );
}
