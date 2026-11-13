// Regression test for the v3.5.5 "grey screen after the splash" bug.
//
// In release builds Flutter swaps any widget that throws during build for a
// translucent grey box. v5.0's AdBanner threw a TypeError on every build, so
// the main menu turned completely grey. This test boots the real app with
// mocked platform plugins and fails on ANY exception while the boot loader,
// splash, menu, level select and shop screens are built.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arrow_puzzle/main.dart';

/// Answers every call on [name]: adaptive banner size -> 50dp, else null.
void _mockChannel(String name) {
  const codec = StandardMethodCodec();
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(name,
      (ByteData? msg) async {
    Object? result;
    try {
      final call = codec.decodeMethodCall(msg);
      if (call.method == 'AdSize#getAnchoredAdaptiveBannerAdSize') {
        result = 50;
      }
    } catch (_) {
      // custom-codec payloads (ad requests): just acknowledge
    }
    return codec.encodeSuccessEnvelope(result);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real Fredoka font so text is measured like on a phone (the default test
  // font draws every glyph as a full square and overflows titles).
  setUpAll(() async {
    final loader = FontLoader('Fredoka');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Fredoka-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() {
    // audio off: audioplayers' periodic position timer would outlive the test
    SharedPreferences.setMockInitialValues({'musicOn': false, 'soundOn': false});
    for (final c in [
      'plugins.flutter.io/google_mobile_ads',
      'plugins.flutter.io/in_app_purchase',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      // event streams opened by every audio player
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers/events/arrows_music',
      for (int i = 0; i < 8; i++) 'xyz.luan/audioplayers/events/arrows_sfx_$i',
    ]) {
      _mockChannel(c);
    }
  });

  testWidgets('boot -> splash -> menu -> levels/shop/game build without errors',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // flutter_test fails this test on ANY exception reported while building
    // (exactly what showed up as the grey screen in release builds).
    await tester.pumpWidget(const ArrowsApp());
    // boot loader: real async work (asset loading, plugin calls)
    for (int i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // splash animation -> menu
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('PLAY'), findsOneWidget, reason: 'menu not reached');
    expect(find.byType(ErrorWidget), findsNothing);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final (route, arg) in [
      ('/levels', null),
      ('/shop', null),
      ('/game', 1),
      ('/game', 11), // first regenerated level
      ('/game', 1000),
    ]) {
      nav.pushNamed(route, arguments: arg);
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ErrorWidget), findsNothing, reason: '$route $arg');
      nav.pop();
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // let looping animations settle before teardown
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10)); // drain pending timers
  }, timeout: const Timeout(Duration(minutes: 3)));
}
