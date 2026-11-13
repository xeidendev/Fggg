import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ads.dart';
import '../core/audio.dart';
import '../core/save.dart';
import '../core/theme.dart';
import 'settings_sheet.dart';
import 'widgets.dart';

/// Main menu: juicy title, floating bokeh background, pulsing play button.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.97,
    upperBound: 1.03,
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final save = GameSave.instance;
    final current = save.maxLevel.clamp(1, 1000);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BokehBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 350),
                        child: RoundIcon(
                          icon: Icons.settings_rounded,
                          onTap: () => showSettingsSheet(context),
                        ),
                      ),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 390),
                        child: RoundIcon(
                          icon: Icons.storefront_rounded,
                          iconColor: AppTheme.blue,
                          onTap: () {
                            GameAudio.play('open');
                            Navigator.pushNamed(context, '/shop');
                          },
                        ),
                      ),
                      const FadeSlideIn(
                        delay: Duration(milliseconds: 420),
                        child: SavedCoinPill(),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                // Title with per-letter wobble
                const _WobbleTitle(),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 260),
                  child: Text(
                    'clear every line — don\u2019t crash the heads',
                    style: AppTheme.body(15, color: AppTheme.inkSoft),
                  ),
                ),
                const Spacer(flex: 3),
                ScaleTransition(
                  scale: _pulse,
                  child: JuicyButton(
                    delay: const Duration(milliseconds: 460),
                    color: AppTheme.blue,
                    height: 76,
                    width: 240,
                    onPressed: () =>
                        Navigator.pushNamed(context, '/game', arguments: current),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 34),
                            const SizedBox(width: 4),
                            Text('PLAY',
                                style: AppTheme.display(26, color: Colors.white)),
                          ],
                        ),
                        Text('LEVEL $current',
                            style: AppTheme.body(13,
                                color: Colors.white.withAlpha(220))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Daily bonus chip (v5.0)
                FadeSlideIn(
                  delay: const Duration(milliseconds: 510),
                  child: _DailyBonusChip(onClaimed: () => setState(() {})),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 560),
                  child: JuicyButton(
                    color: AppTheme.ink,
                    height: 58,
                    width: 240,
                    onPressed: () => Navigator.pushNamed(context, '/levels'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.grid_view_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text('LEVELS',
                            style: AppTheme.title(18, color: Colors.white)),
                        const SizedBox(width: 10),
                        Text('${save.totalStars}',
                            style: AppTheme.title(16,
                                color: AppTheme.gold)),
                        const Icon(Icons.star_rounded,
                            color: AppTheme.gold, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 660),
                  child: Text(
                    'v3.5.5 · 1000 levels',
                    style: AppTheme.body(13, color: AppTheme.inkSoft),
                  ),
                ),
                const SizedBox(height: 8),
                // AdMob anchored banner (v5.0) — hidden when ads removed
                const AdBanner(),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WobbleTitle extends StatelessWidget {
  const _WobbleTitle();

  final List<Color> _letterColors = const [
    AppTheme.blue,
    AppTheme.red,
    AppTheme.gold,
    AppTheme.green,
    AppTheme.purple,
    AppTheme.blue,
  ];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 'ARROWS'.length; i++)
            Stack(
              children: [
                Text('ARROWS'[i],
                    style: AppTheme.display(64, color: AppTheme.ink)),
                Text('ARROWS'[i],
                    style: AppTheme.display(64,
                        color: _letterColors[i % _letterColors.length]
                            .withAlpha(28))),
              ],
            ),
        ],
      ),
    );
  }
}

/// Soft floating background blobs.
class _BokehBackground extends StatefulWidget {
  const _BokehBackground();

  @override
  State<_BokehBackground> createState() => _BokehBackgroundState();
}

class _BokehBackgroundState extends State<_BokehBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _BokehPainter(t: t),
        );
      },
    );
  }
}

class _BokehPainter extends CustomPainter {
  _BokehPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7F2EB), Color(0xFFEFE6DA)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final blobs = [
      (0.15, 0.2, 90.0, 0.05, const Color(0x14328BF3)),
      (0.85, 0.3, 70.0, 0.03, const Color(0x14F6B51E)),
      (0.25, 0.75, 110.0, 0.04, const Color(0x103DBB7D)),
      (0.75, 0.85, 60.0, 0.06, const Color(0x128A5CF6)),
      (0.5, 0.5, 130.0, 0.02, const Color(0x0AD2352F)),
    ];
    for (final b in blobs) {
      final bx = (b.$1 + 0.06 * math.sin(t * 2 * math.pi + b.$1 * 9)) * size.width;
      final by = (b.$2 + 0.05 * math.cos(t * 2 * math.pi + b.$2 * 7)) * size.height;
      canvas.drawCircle(
          Offset(bx, by), b.$3, Paint()..color = b.$5);
    }
  }

  @override
  bool shouldRepaint(covariant _BokehPainter old) => old.t != t;
}

/// Daily bonus chip: +40 coins once per calendar day (v5.0).
class _DailyBonusChip extends StatelessWidget {
  const _DailyBonusChip({required this.onClaimed});

  final VoidCallback onClaimed;

  @override
  Widget build(BuildContext context) {
    final save = GameSave.instance;
    final ready = save.dailyBonusReady;
    return GestureDetector(
      onTap: ready
          ? () {
              save.claimDailyBonus();
              GameAudio.playSynth('coin');
              onClaimed();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppTheme.ink,
                  content: Text(
                    'Daily bonus: +${GameSave.dailyBonusCoins} coins! Come back tomorrow for more.',
                    style: AppTheme.body(14, color: Colors.white),
                  ),
                  duration: const Duration(milliseconds: 1600),
                ),
              );
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: ready ? AppTheme.gold : AppTheme.paperDark,
          borderRadius: BorderRadius.circular(999),
          boxShadow: ready
              ? const [
                  BoxShadow(
                      color: Color(0x33F6B51E),
                      offset: Offset(0, 4),
                      blurRadius: 8),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.redeem_rounded : Icons.lock_clock_rounded,
              size: 20,
              color: ready ? Colors.white : AppTheme.inkSoft,
            ),
            const SizedBox(width: 8),
            Text(
              ready
                  ? 'DAILY BONUS  +${GameSave.dailyBonusCoins}'
                  : 'Daily bonus in ${save.hoursUntilDailyBonus()}h',
              style: AppTheme.title(
                14,
                color: ready ? Colors.white : AppTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
