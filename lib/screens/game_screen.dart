import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/audio.dart';
import '../core/ads.dart';
import '../core/engine.dart';
import '../core/levels_data.dart';
import '../core/save.dart';
import '../core/solver.dart';
import '../core/theme.dart';
import '../game/board_transform.dart';
import '../game/fx.dart';
import '../game/painter.dart';
import 'settings_sheet.dart';
import 'widgets.dart';

const int kMaxLevel = 1000;

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.level});

  final int level; // 1-based

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late PuzzleEngine engine;
  late FxSystem fx;
  Duration _last = Duration.zero;
  double time = 0;
  int? hintIndex;
  double hintUntil = 0;
  int heartPopIndex;
  bool winShown = false;
  bool loseShown = false;
  int starsEarned = 0;
  int coinsEarned = 0;
  int coinsShown = 0;
  bool coinsDoubled = false;
  bool newBest = false;
  Offset? _winCoinFrom;

  /// Line highlighted while the finger is down (launches on release).
  int? pressIndex;
  BoardTransform? _xform;
  bool continuingAfterAd = false;

  _GameScreenState() : heartPopIndex = -1;

  @override
  void initState() {
    super.initState();
    _buildLevel();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _buildLevel() {
    final def = Levels.instance[widget.level - 1];
    fx = FxSystem();
    engine = PuzzleEngine(
      def,
      idx: widget.level - 1,
      onCollide: (i, at) {
        fx.hitSparks(at);
        GameAudio.play('collide');
        if (GameSave.instance.hapticsOn) HapticFeedback.mediumImpact.call();
        setState(() => heartPopIndex = engine.hearts);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => heartPopIndex = -1);
        });
      },
      onClear: (i, at) {
        fx.clearBurst(at, LineTheme.byId(GameSave.instance.themeId).line);
        GameAudio.playSynth('pop');
      },
      onLaunch: (i) {
        GameAudio.play('move');
        if (GameSave.instance.hapticsOn) HapticFeedback.lightImpact.call();
        if (hintIndex == i) setState(() => hintIndex = null);
      },
    );
    winShown = false;
    loseShown = false;
    starsEarned = 0;
    coinsEarned = 0;
    coinsShown = 0;
    coinsDoubled = false;
    newBest = false;
    heartPopIndex = -1;
    hintIndex = null;
    pressIndex = null;
    continuingAfterAd = false;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    time += dt;
    if (!winShown && !loseShown) {
      engine.tick(dt);
      if (engine.won && !winShown) {
        _onWin();
      } else if (engine.lost && !loseShown) {
        _onLose();
      }
    }
    fx.tick(dt);
    if (hintIndex != null && time > hintUntil) {
      setState(() => hintIndex = null);
    }
    // painter repaints via CustomPainter repaint listenable below
    _repaint.value = time;
  }

  final ValueNotifier<double> _repaint = ValueNotifier<double>(0);

  void _onWin() {
    final save = GameSave.instance;
    starsEarned = engine.stars();
    final oldBest = save.starsAt(widget.level);
    newBest = starsEarned > oldBest;
    save.setStars(widget.level, starsEarned);
    if (widget.level + 1 > save.maxLevel) {
      save.setMaxLevel(math.min(kMaxLevel, widget.level + 1));
    }
    coinsEarned = engine.def.winCoins + starsEarned * 5 + (engine.perfect ? 10 : 0);
    save.addCoins(coinsEarned);
    winShown = true;
    setState(() {});
    // Full-length victory fanfare on its own player — the SFX pool (star dings,
    // coin count-up) can no longer cut it short, and BGM resumes afterwards.
    GameAudio.playWinJingle();
    if (GameSave.instance.hapticsOn) HapticFeedback.heavyImpact.call();
    // staggered star dings
    for (int i = 0; i < starsEarned; i++) {
      Future.delayed(Duration(milliseconds: 500 + i * 340), () {
        if (!mounted) return;
        GameAudio.playSynth('star');
        fx.starPop(_starWorldPos(i));
      });
    }
    // coin count-up
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _countUpCoins();
    });
  }

  void _countUpCoins() {
    if (coinsShown >= coinsEarned) return;
    setState(() {
      coinsShown = math.min(coinsEarned, coinsShown + 2);
    });
    if (coinsShown % 4 == 0) GameAudio.playSynth('count');
    if (coinsShown % 6 == 0 && _winCoinFrom != null) {
      fx.coinFlight(_winCoinFrom!, const Offset(0, 0), count: 2);
    }
    Future.delayed(const Duration(milliseconds: 40), () {
      if (mounted && winShown) _countUpCoins();
    });
  }

  Offset _starWorldPos(int i) {
    final boardSize = _xform?.boardSize ?? MediaQuery.of(context).size;
    final view = engine.computeView(boardSize.width / boardSize.height);
    final dx = (i - 1) * view.ortho * 0.32;
    return Offset(view.center.dx + dx, view.center.dy + view.ortho * 0.1);
  }

  void _onLose() {
    loseShown = true;
    setState(() {});
    GameAudio.play('lose');
  }

  /// Rewarded-ad continue: refill 3 hearts and keep playing.
  void _continueAfterAd() {
    GameAudio.play('confirm');
    setState(() {
      engine.continueWithHearts(3);
      loseShown = false;
      continuingAfterAd = true;
      pressIndex = null;
    });
    fx.continueBurst(engine.computeView(_xform!.boardSize.aspectRatio).center);
    if (GameSave.instance.hapticsOn) HapticFeedback.heavyImpact.call();
  }

  /// Rewarded-ad double coins on the win screen.
  void _doubleCoins() {
    if (coinsDoubled) return;
    setState(() {
      coinsDoubled = true;
      final added = coinsEarned; // original grant from _onWin
      coinsEarned += added;
      GameSave.instance.addCoins(added);
    });
    GameAudio.playSynth('coin');
    _countUpCoins();
  }

  // ---- input ----
  // v5.0: the finger PICKS on press-down (line lights up), and the launch
  // happens on release ONLY if the same line is still under the finger.
  // What you saw highlighted is exactly what fires — no more wrong arrows.
  void _onPressDown(Offset localPos, Size boardSize) {
    if (winShown || loseShown || _xform == null) return;
    final world = _xform!.screenToWorld(localPos);
    final idx = engine.previewAt(world, slopRadius: _slopWorld);
    setState(() => pressIndex = idx);
    if (idx != null && GameSave.instance.hapticsOn) {
      HapticFeedback.selectionClick.call();
    }
  }

  void _onPressUp(Offset localPos, Size boardSize) {
    if (winShown || loseShown || _xform == null) return;
    final idx = pressIndex;
    setState(() => pressIndex = null);
    if (idx == null) return;
    final world = _xform!.screenToWorld(localPos);
    final stillSame = engine.previewAt(world, slopRadius: _slopWorld) == idx;
    fx.tapRipple(_xform!.screenToWorld(localPos));
    if (stillSame && engine.tapLine(idx)) {
      // launch fx handled by onLaunch callback
    } else if (!stillSame) {
      GameAudio.play('close');
    }
  }

  void _onPressCancel() {
    if (pressIndex != null) setState(() => pressIndex = null);
  }

  /// ~34 logical px of finger tolerance, in world units, clamped so it can
  /// never bridge two lines on zoomed-out boards.
  double get _slopWorld => (_xform?.pxToWorld(34) ?? 0.9).clamp(0.4, 0.9);

  // ---- ui actions ----
  void _restart() {
    GameAudio.play('confirm');
    setState(() {
      _buildLevel();
      _last = Duration.zero;
    });
  }

  void _next() {
    if (widget.level >= kMaxLevel) {
      Ads.onLevelCompleted(); // interstitial cadence also counts final exits
      Navigator.of(context).pushReplacementNamed('/menu');
      return;
    }
    GameAudio.play('confirm');
    // v5.0 monetisation: full-screen interstitial after every 3rd completed
    // level (skipped entirely when "Remove ads" was purchased).
    Ads.onLevelCompleted();
    Navigator.of(context).pushReplacementNamed('/game', arguments: widget.level + 1);
  }

  void _hint() {
    final save = GameSave.instance;
    if (save.coins < 25) {
      GameAudio.play('close');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.ink,
          content: Text('Hints cost 25 coins — win levels to earn more!',
              style: AppTheme.body(14, color: Colors.white)),
          duration: const Duration(milliseconds: 1300),
        ),
      );
      return;
    }
    final h = Solver.hint(engine);
    if (h == null) {
      GameAudio.play('close');
      return;
    }
    save.addCoins(-25);
    GameAudio.playSynth('whoosh');
    setState(() {
      hintIndex = h;
      hintUntil = time + 3.5;
    });
  }

  void _menu() {
    GameAudio.play('close');
    Navigator.of(context).pushNamedAndRemoveUntil('/menu', (r) => false);
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // board
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              // ONE transform shared by painter + gestures: the tap always
              // lands on the arrow drawn under the finger (v5.0 fatal fix).
              final xform = BoardTransform(
                view: engine.computeView(size.width / size.height),
                boardSize: size,
              );
              _xform = xform;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onPressDown(d.localPosition, size),
                onTapUp: (d) => _onPressUp(d.localPosition, size),
                onTapCancel: _onPressCancel,
                child: CustomPaint(
                  size: size,
                  painter: ArrowsPainter(
                    engine: engine,
                    fx: fx,
                    theme: LineTheme.byId(GameSave.instance.themeId),
                    xform: xform,
                    time: time,
                    hintIndex: hintIndex,
                    previewIndex: pressIndex,
                    dimmed: winShown || loseShown,
                    repaint: _repaint,
                  ),
                  isComplex: true,
                  willChange: true,
                ),
              );
            },
          ),
          // HUD
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      RoundIcon(
                        icon: Icons.arrow_back_rounded,
                        size: 44,
                        onTap: _menu,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.white,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x1E241E33),
                                      offset: Offset(0, 3),
                                      blurRadius: 6)
                                ],
                              ),
                              child: Text(
                                'LEVEL ${widget.level}',
                                style: AppTheme.display(16),
                              ),
                            ),
                            const SizedBox(height: 6),
                            HeartRow(
                              hearts: engine.hearts,
                              maxHearts: engine.maxHearts,
                              popIndex: heartPopIndex,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      RoundIcon(
                        icon: Icons.pause_rounded,
                        size: 44,
                        onTap: () => _showPauseSheet(context, this),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // bottom row: hint + coins
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      JuicyButton(
                        color: AppTheme.gold,
                        height: 46,
                        width: 108,
                        enableSound: false,
                        onPressed: engine.won || engine.lost ? null : _hint,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lightbulb_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 5),
                            Text('25',
                                style: AppTheme.body(14,
                                    color: Colors.white, w: FontWeight.w700)),
                            const Icon(Icons.bolt_rounded,
                                color: Colors.white, size: 15),
                          ],
                        ),
                      ),
                      const SavedCoinPill(fontSize: 15),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // overlays
          if (winShown) _WinOverlay(state: this),
          if (loseShown) _LoseOverlay(state: this),
          if (!winShown && !loseShown && engine.started && engine.remaining > 0)
            Positioned(
              top: 86,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: _ProgressBar(
                    progress: 1 - engine.remaining / engine.lines.length,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    fx.dispose();
    super.dispose();
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0x2E3A3633),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.green,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- WIN OVERLAY ----------------

class _WinOverlay extends StatefulWidget {
  const _WinOverlay({required this.state});

  final _GameScreenState state;

  @override
  State<_WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<_WinOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();
  late final List<Confetti> _confetti;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _confetti = [
      for (int i = 0; i < 130; i++)
        Confetti(
          x: rng.nextDouble(),
          y: -rng.nextDouble() * 0.9,
          speed: 0.35 + rng.nextDouble() * 0.5,
          sway: rng.nextDouble() * 2 * math.pi,
          size: 6 + rng.nextDouble() * 8,
          color: _colors[rng.nextInt(_colors.length)],
          spin: (rng.nextDouble() - 0.5) * 8,
        )
    ];
    _c.addListener(() {
      const dt = 1 / 60.0;
      for (final cf in _confetti) {
        cf.y += cf.speed * dt;
        cf.x += math.sin(cf.y * 9 + cf.sway) * 0.0012;
        cf.rot += cf.spin * dt;
        if (cf.y > 1.1) {
          cf.y = -0.05;
        }
      }
      if (mounted) setState(() {});
    });
  }

  static const _colors = [
    AppTheme.blue,
    AppTheme.red,
    AppTheme.gold,
    AppTheme.green,
    AppTheme.purple,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stars = widget.state.starsEarned;
    final perfect = widget.state.engine.perfect;
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // dim + blur backdrop
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _ConfettiPainter(confetti: _confetti, t: _c.value),
              child: Container(
                color: const Color(0x64141E33),
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // LEVEL COMPLETE pop
                      ScaleTransition(
                        scale: _pop(_c, 0.0, 0.5),
                        child: Text(
                          'LEVEL COMPLETE!',
                          textAlign: TextAlign.center,
                          style: AppTheme.display(34, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (perfect)
                        ScaleTransition(
                          scale: _pop(_c, 0.25, 0.5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.gold,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bolt_rounded,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 4),
                                Text('PERFECT!',
                                    style: AppTheme.title(16,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      if (!perfect && widget.state.continuingAfterAd)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('SECOND CHANCE — nice recovery!',
                              style: AppTheme.title(14,
                                  color: AppTheme.gold)),
                        ),
                      const SizedBox(height: 22),
                      // stars slam in
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < 3; i++)
                            _StarSlam(
                              c: _c,
                              index: i,
                              on: i < stars,
                              delay: 0.35 + i * 0.2,
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (widget.state.newBest)
                        FadeTransition(
                          opacity: _fade(_c, 0.75, 1.0),
                          child: Text('NEW BEST!',
                              style: AppTheme.title(15,
                                  color: AppTheme.gold)),
                        ),
                      const SizedBox(height: 10),
                      // coins
                      ScaleTransition(
                        scale: _pop(_c, 0.7, 0.6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _CoinBadge(),
                              const SizedBox(width: 8),
                              Text(
                                '+${widget.state.coinsShown}',
                                style: AppTheme.display(24),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // DOUBLE COINS — rewarded ad (v5.0). Hidden once used
                      // or when ads are removed via the IAP.
                      if (!widget.state.coinsDoubled &&
                          !GameSave.instance.adsRemoved)
                        ScaleTransition(
                          scale: _pop(_c, 0.8, 0.55),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: JuicyButton(
                              color: AppTheme.purple,
                              height: 52,
                              width: 272,
                              onPressed: () => Ads.showRewarded(
                                context,
                                adLabel: 'double coins',
                                onReward: widget.state._doubleCoins,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.movie_rounded,
                                      color: Colors.white, size: 22),
                                  const SizedBox(width: 8),
                                  Text('DOUBLE COINS',
                                      style: AppTheme.title(16,
                                          color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      // buttons pop in sequence
                      ScaleTransition(
                        scale: _pop(_c, 0.85, 0.7),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            JuicyButton(
                              color: AppTheme.ink,
                              height: 56,
                              width: 130,
                              onPressed: widget.state._menu,
                              child: Text('MENU',
                                  style: AppTheme.title(16,
                                      color: Colors.white)),
                            ),
                            const SizedBox(width: 12),
                            JuicyButton(
                              color: AppTheme.paperDark,
                              height: 56,
                              width: 130,
                              onPressed: widget.state._restart,
                              child: const Icon(Icons.replay_rounded,
                                  color: AppTheme.ink, size: 26),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ScaleTransition(
                        scale: _pop(_c, 0.95, 0.7),
                        child: JuicyButton(
                          color: AppTheme.green,
                          height: 62,
                          width: 272,
                          onPressed: widget.state._next,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('NEXT LEVEL',
                                  style: AppTheme.title(18,
                                      color: Colors.white)),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Animation<double> _pop(AnimationController c, double start, double end) {
    final a = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: c,
        curve: Interval(start, (start + end).clamp(0.0, 1.0),
            curve: Curves.elasticOut),
      ),
    );
    return a;
  }

  static Animation<double> _fade(AnimationController c, double s, double e) {
    return Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: c, curve: Interval(s, e, curve: Curves.easeOut)),
    );
  }
}

class _CoinBadge extends StatelessWidget {
  const _CoinBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        color: AppTheme.gold,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD970),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB27E00), width: 2),
          ),
        ),
      ),
    );
  }
}

class _StarSlam extends StatelessWidget {
  const _StarSlam({
    required this.c,
    required this.index,
    required this.on,
    required this.delay,
  });

  final AnimationController c;
  final int index;
  final bool on;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final a = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: c,
        curve: Interval(delay, (delay + 0.22).clamp(0.0, 1.0),
            curve: Curves.elasticOut),
      ),
    );
    return AnimatedBuilder(
      animation: a,
      builder: (context, _) {
        final v = a.value;
        return Transform.scale(
          scale: v,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.star_rounded,
              size: index == 1 ? 74 : 58,
              color: on && v > 0.1
                  ? AppTheme.gold
                  : Colors.white.withAlpha(70),
              shadows: on && v > 0.1
                  ? const [
                      Shadow(color: Color(0x66F6B51E), blurRadius: 24),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class Confetti {
  Confetti({
    required this.x,
    required this.y,
    required this.speed,
    required this.sway,
    required this.size,
    required this.color,
    required this.spin,
    this.rot = 0,
  });

  double x;
  double y;
  double speed;
  double sway;
  double size;
  Color color;
  double spin;
  double rot;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.confetti, required this.t});

  final List<Confetti> confetti;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final cf in confetti) {
      if (cf.y * size.height > size.height) continue;
      final pos = Offset(cf.x * size.width, cf.y * size.height);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(cf.rot);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: cf.size,
          height: cf.size * 0.6,
        ),
        Paint()..color = cf.color.withAlpha((180 * t.clamp(0.3, 1.0)).toInt()),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}

// ---------------- LOSE OVERLAY ----------------

class _LoseOverlay extends StatefulWidget {
  const _LoseOverlay({required this.state});

  final _GameScreenState state;

  @override
  State<_LoseOverlay> createState() => _LoseOverlayState();
}

class _LoseOverlayState extends State<_LoseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x64241E33),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (context, v, child) =>
            Transform.scale(scale: v.clamp(0.0, 1.2), child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.heart_broken_rounded,
                color: AppTheme.red, size: 64),
            const SizedBox(height: 10),
            Text('OUT OF HEARTS',
                style: AppTheme.display(30, color: Colors.white)),
            const SizedBox(height: 6),
            Text('crashing the arrow head costs a heart',
                style: AppTheme.body(14, color: Colors.white.withAlpha(200))),
            const SizedBox(height: 26),
            // CONTINUE — rewarded ad refills 3 hearts (v5.0)
            if (!GameSave.instance.adsRemoved)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: JuicyButton(
                  color: AppTheme.green,
                  height: 56,
                  width: 272,
                  onPressed: () => Ads.showRewarded(
                    context,
                    adLabel: '3 extra hearts',
                    onReward: widget.state._continueAfterAd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text('CONTINUE · +3 HEARTS',
                          style: AppTheme.title(15, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                JuicyButton(
                  color: AppTheme.ink,
                  height: 56,
                  width: 130,
                  onPressed: widget.state._menu,
                  child:
                      Text('MENU', style: AppTheme.title(16, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                JuicyButton(
                  color: AppTheme.blue,
                  height: 56,
                  width: 130,
                  onPressed: widget.state._restart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.replay_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 6),
                      Text('RETRY',
                          style: AppTheme.title(16, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- PAUSE SHEET ----------------

void _showPauseSheet(BuildContext context, _GameScreenState state) {
  GameAudio.play('open');
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Paused', textAlign: TextAlign.center,
                  style: AppTheme.display(26)),
              const SizedBox(height: 18),
              JuicyButton(
                color: AppTheme.blue,
                onPressed: () {
                  GameAudio.play('close');
                  Navigator.pop(context);
                },
                child: Text('RESUME',
                    style: AppTheme.title(17, color: Colors.white)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: JuicyButton(
                      color: AppTheme.paperDark,
                      height: 54,
                      onPressed: () {
                        Navigator.pop(context);
                        state._restart();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.replay_rounded,
                              color: AppTheme.ink, size: 22),
                          const SizedBox(width: 6),
                          Text('RESTART', style: AppTheme.title(15)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: JuicyButton(
                      color: AppTheme.paperDark,
                      height: 54,
                      onPressed: () {
                        Navigator.pop(context);
                        state._menu();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.home_rounded,
                              color: AppTheme.ink, size: 22),
                          const SizedBox(width: 6),
                          Text('MENU', style: AppTheme.title(15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: JuicyButton(
                      color: AppTheme.paperDark,
                      height: 54,
                      enableSound: false,
                      onPressed: () => showSettingsSheet(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.settings_rounded,
                              color: AppTheme.ink, size: 22),
                          const SizedBox(width: 6),
                          Text('SETTINGS', style: AppTheme.title(15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
