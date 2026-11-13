# Arrows — Flutter Remake (v3.5.5)

A faithful Flutter remake of the Unity original (SERAP-KEREM/Arrows), rebuilt
with a juicy, animated UI and **1000 levels**.

## What's inside
- `lib/` — game source
  - `core/engine.dart` — sliding-window line mechanics (Unity physics parity)
  - `core/solver.dart` — solver + lookahead bot (level validation, hints)
  - `core/levels_data.dart` — level loading (1000 levels, JSON asset)
  - `core/sfx_synth.dart`, `music_bank.dart` — procedural SFX + BGM,
    including the full-length victory fanfare (`SynthWav.winFanfare`)
  - `core/ads.dart` — AdMob (banner / interstitial / rewarded) + `AdConfig`
  - `core/billing.dart` — Google Play Billing (coin packs, remove ads)
  - `game/board_transform.dart` — THE tap-accuracy fix (single shared
    world<->screen transform used by painter AND gestures)
  - `game/fx.dart`, `game/painter.dart` — particles, shake, glow rendering
  - `screens/` — splash, main menu, level select, game, shop, settings, overlays
- `assets/levels/levels.json` — all 1000 levels (10 original Unity levels +
  990 generated, every one solver-verified solvable)
- `android/key/arrows-release.keystore` + `android/key.properties` — release
  signing key and credentials. Kept OUT of git (see `android/.gitignore`);
  keep your own backup, every Play update must be signed with the same key.

## v3.5.5 changes
- **Levels 11–1000 regenerated.** The old generator scattered a few straight
  lines on an empty board: lines crossed each other, arrowheads sat on top of
  other lines, arrows flew back over their own body, and the difficulty fell
  from 40 lines (level 10) to 4 lines (level 11). The new generator
  (`tools/gen_1000_levels.py`) packs the board densely with snake-shaped
  arrows like the 10 original levels: every grid point belongs to at most one
  line, boards are centred, and size/line count/turns ramp up smoothly
  (~20 lines at level 11 up to ~60–70 lines at level 1000). Every level is
  verified solvable with an exact port of the engine's collision rules and
  again by `flutter test`.
- New tests: no crossings/shared points, no self-crossing flights, no
  difficulty cliff after level 10.
- **minSdk 24** — Google Play's automatic protection rejects bundles with
  minSdkVersion below 24.
- **Grey screen after the splash fixed.** `AdBanner` cast the Future
  returned by `AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize` to
  `AdSize?`, which threw on every build; in release builds Flutter shows a
  widget that throws as a translucent grey box, which covered the whole
  menu. The size is now awaited and any ad failure just hides the banner.
  New `test/app_flow_test.dart` boots the real app (mocked plugins) through
  splash, menu, level select, shop and game and fails on any build error.
- Version 3.5.5 (versionCode 356).
- **32-bit APK crash fix**: the build now packages only the ABIs being
  targeted (`ndk.abiFilters` from `target-platform`). Before, plugin `.so`
  files created a stray `lib/arm64-v8a` folder in the 32-bit APK, so 64-bit
  phones looked there, found no Flutter engine and crashed on launch.
- Built APKs/AAB for this version are in `releases/v3.5.5/`.
- Removed machine-specific Gradle settings (hard-coded JDK path, local maven
  folder, Aliyun mirrors) so the project builds on any machine.

## v5.0 changes (fatal tap bug fix)
- **FATAL FIX — taps activating the wrong arrow.** The painter mapped world→
  screen with `scale = max(ortho*2/W, ortho*2/H)` while the tap path mapped
  screen→world with `scale = ortho*2/H` only. On any portrait phone (H > W)
  the two differed by H/W (~2.2x), so every tap away from the board centre
  drifted toward the middle and fired a neighbour. Both paths now share ONE
  `BoardTransform` (`lib/game/board_transform.dart`) — parity by construction.
- Tap UX: press-down now **highlights the exact line that will launch**;
  releasing fires it (drag off = cancel). Arrowheads are grab targets, so a
  head under the finger always wins over a crossing stroke.
- Pixel-derived tap slop (34 px, clamped) — same finger accuracy at every
  zoom level; direct-hit band so strokes beat loose slop of neighbours.
- **AdMob**: anchored adaptive banners (menu / levels / shop), interstitial
  every 3 completed levels, rewarded ads (double coins on win, continue with
  +3 hearts on lose, free coins in shop). Google TEST ids in `AdConfig` +
  manifest — swap in your real ids before publishing.
- **Google Play Billing**: 4 consumable coin packs + "Remove ads"
  (non-consumable) + restore purchases. Product ids in `BillingConfig`;
  create matching in-app products in Play Console.
- **Shop screen** (menu → storefront icon), **daily bonus** (+40 coins/day),
  "SECOND CHANCE" badge, fail-safe everywhere (offline never blocks play).
- Release builds are signed with the shipped keystore, R8-minified;
  minSdk 23 (raised to 24 in v3.5.5); Gradle 8.7 / AGP 8.3.2 / Kotlin 1.9.24 (JDK 17/21).
- Universal APK (arm64-v8a + armeabi-v7a + x86_64) and a 32-bit-only APK
  (`--target-platform android-arm`).

## v4.0 changes
- Package name **`com.Exilux.arrow_puzzle`**; custom launcher icons.
- Win music fix: full-length fanfare on a dedicated media player.

## Build
```
flutter pub get
flutter build apk --release --no-tree-shake-icons              # universal
flutter build apk --release --target-platform android-arm      # 32-bit
flutter build appbundle --release                              # Play Store
```
Requires Flutter 3.24.x, JDK 17+, Android SDK 34/35.

## Validation ("make no mistakes")
- `flutter test` — 54 tests: engine mechanics, BoardTransform paint/tap
  parity, tap-accuracy regression across 60 sampled levels (unambiguous taps
  MUST fire their own line), launch-on-release, ALL 1000 levels
  solver-verified, bot clears sampled levels with 5 hearts and zero
  collisions, fanfare WAV integrity.

## Gameplay
Tap a line — its head flies out along the final segment while the tail follows
(constant length). Clear every line without crashing a head into another line.
Crashing costs a heart (5 hearts). Stars by completion time; earn coins to
unlock arrow styles; hints cost 25 coins; watch a rewarded ad to double win
coins or continue after losing.
