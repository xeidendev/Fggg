import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/audio.dart';
import '../core/save.dart';
import '../core/theme.dart';

/// Bouncy press-scale button with pop-in entrance and click sfx.
class JuicyButton extends StatefulWidget {
  const JuicyButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.width,
    this.height = 64,
    this.color = AppTheme.blue,
    this.shadow,
    this.delay = Duration.zero,
    this.enableSound = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double? width;
  final double height;
  final Color color;
  final Color? shadow;
  final Duration delay;
  final bool enableSound;

  @override
  State<JuicyButton> createState() => _JuicyButtonState();
}

class _JuicyButtonState extends State<JuicyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _in = CurvedAnimation(
      parent: _c, curve: const ElasticOutCurve(0.55));
  double _press = 1;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return ScaleTransition(
      scale: _in,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _press = 0.93) : null,
        onTapCancel: enabled ? () => setState(() => _press = 1) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _press = 1);
                if (widget.enableSound) GameAudio.play('click');
                HapticFeedback.lightImpact.call();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _press,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: enabled ? widget.color : widget.color.withAlpha(110),
              borderRadius: BorderRadius.circular(widget.height / 2),
              boxShadow: [
                BoxShadow(
                  color: (widget.shadow ?? widget.color).withAlpha(80),
                  offset: const Offset(0, 6),
                  blurRadius: 0.5,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Round icon button (settings, back...).
class RoundIcon extends StatefulWidget {
  const RoundIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 52,
    this.iconSize = 26,
    this.color = AppTheme.white,
    this.iconColor = AppTheme.ink,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;

  @override
  State<RoundIcon> createState() => _RoundIconState();
}

class _RoundIconState extends State<RoundIcon> {
  double _press = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _press = 0.9),
      onTapCancel: () => setState(() => _press = 1),
      onTapUp: (_) {
        setState(() => _press = 1);
        GameAudio.play('click');
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _press,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33241E33),
                offset: Offset(0, 3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(widget.icon, size: widget.iconSize, color: widget.iconColor),
        ),
      ),
    );
  }
}

/// Animated coin counter with rolling number.
class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins, this.fontSize = 18});

  final int coins;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x22241E33), offset: Offset(0, 3), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CoinIcon(size: 20),
          const SizedBox(width: 7),
          TweenAnimationBuilder<int>(
            tween: IntTween(end: coins),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              '$v',
              style: AppTheme.body(fontSize, w: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinIcon extends StatelessWidget {
  const _CoinIcon({this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _CoinPainter());
  }
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = AppTheme.gold);
    canvas.drawCircle(
        c, r * 0.72, Paint()..color = const Color(0xFFFFD970));
    final p = Paint()
      ..color = const Color(0xFFB27E00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.14;
    canvas.drawCircle(c, r * 0.72, p);
  }

  @override
  bool shouldRepaint(covariant _CoinPainter old) => false;
}

/// Heart row with loss animation hook.
class HeartRow extends StatelessWidget {
  const HeartRow({
    super.key,
    required this.hearts,
    required this.maxHearts,
    this.size = 26,
    this.popIndex,
  });

  final int hearts;
  final int maxHearts;
  final double size;
  final int? popIndex; // index currently popping (just lost)

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < maxHearts; i++)
          _Heart(
            filled: i < hearts,
            size: size,
            pop: popIndex == i,
          ),
      ],
    );
  }
}

class _Heart extends StatefulWidget {
  const _Heart({required this.filled, required this.size, required this.pop});

  final bool filled;
  final double size;
  final bool pop;

  @override
  State<_Heart> createState() => _HeartState();
}

class _HeartState extends State<_Heart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant _Heart old) {
    super.didUpdateWidget(old);
    _run();
  }

  void _run() {
    if (widget.pop) {
      _c.forward(from: 0);
    }
  }

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
        final wig = widget.pop ? math.sin(t * math.pi * 3) * (1 - t) * 0.5 : 0.0;
        return Transform.scale(
          scale: widget.pop ? 1 + wig : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _HeartPainter(
                filled: widget.filled,
                t: widget.pop ? t : 0,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeartPainter extends CustomPainter {
  _HeartPainter({required this.filled, required this.t});

  final bool filled;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.9)
      ..cubicTo(-w * 0.28, h * 0.42, w * 0.08, -h * 0.16, w * 0.5, h * 0.24)
      ..cubicTo(w * 0.92, -h * 0.16, w * 1.28, h * 0.42, w * 0.5, h * 0.9)
      ..close();
    final paint = Paint()..color = filled ? AppTheme.red : const Color(0xFFD8CFC4);
    if (filled && t > 0 && t < 1) {
      paint.color = Color.lerp(AppTheme.red, const Color(0xFF88837E), t)!;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) =>
      old.filled != filled || old.t != t;
}

/// Slide+fade entrance helper.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = const Offset(0, 0.25),
  });

  final Widget child;
  final Duration delay;
  final Offset from;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, v, child) {
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(from.dx * (1 - v) * 100, from.dy * (1 - v) * 100),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Reads save and renders the coin pill (stream-less; rebuild on parent).
class SavedCoinPill extends StatelessWidget {
  const SavedCoinPill({super.key, this.fontSize = 18});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return CoinPill(coins: GameSave.instance.coins, fontSize: fontSize);
  }
}
