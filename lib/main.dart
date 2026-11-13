import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/ads.dart';
import 'core/audio.dart';
import 'core/billing.dart';
import 'core/levels_data.dart';
import 'core/save.dart';
import 'core/theme.dart';
import 'screens/game_screen.dart';
import 'screens/level_select_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/splash_screen.dart';
Future<void> main() async {
  // keep splash visible on white before first frame
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runApp(const ArrowsApp());
}

class ArrowsApp extends StatelessWidget {
  const ArrowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arrows',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const BootLoader(),
      // juicy shared transitions
      onGenerateRoute: (settings) {
        final args = settings.arguments;
        Widget page;
        switch (settings.name) {
          case '/menu':
            page = const MenuScreen();
            break;
          case '/levels':
            page = const LevelSelectScreen();
            break;
          case '/shop':
            page = const ShopScreen();
            break;
          case '/splash':
            page = const SplashScreen();
            break;
          case '/game':
            page = GameScreen(level: (args as int?) ?? 1);
            break;
          default:
            page = const MenuScreen();
        }
        return PageRouteBuilder(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) {
            final curved =
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

/// Loads levels + save + audio before revealing the splash.
class BootLoader extends StatefulWidget {
  const BootLoader({super.key});

  @override
  State<BootLoader> createState() => _BootLoaderState();
}

class _BootLoaderState extends State<BootLoader> {
  String _status = 'Loading…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final save = await GameSave.init();
      await Levels.load(() => rootBundle.loadString('assets/levels/levels.json'));
      await GameAudio.init(sound: save.soundOn, music: save.musicOn);
      if (save.musicOn) {
        unawaited(GameAudio.startMusic());
      }
      // v5.0 monetisation — both are fail-safe and never block boot.
      await Ads.init();
      unawaited(Billing.instance.init());
    } catch (e) {
      _status = 'Error: $e';
    }
    if (mounted) {
      setState(() {});
      // brief beat so the loader never flashes
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/splash');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CoinIconLoader(),
            const SizedBox(height: 18),
            Text(_status, style: AppTheme.body(15, color: AppTheme.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _CoinIconLoader extends StatelessWidget {
  const _CoinIconLoader();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      builder: (context, v, _) => Transform.rotate(
        angle: v * 6.28,
        child: const Icon(Icons.play_arrow_rounded, size: 52, color: AppTheme.blue),
      ),
      onEnd: () {},
    );
  }
}

// tiny helper (avoid async dependency)
void unawaited(Future<void> f) {}
