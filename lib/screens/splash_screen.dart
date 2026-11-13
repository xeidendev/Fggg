import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Animated intro: three arrows assemble the logo, then bounce to the menu.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
        ..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacementNamed('/menu');
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(painter: _LogoPainter(t: t)),
                ),
                const SizedBox(height: 26),
                // per-letter bouncing title
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < 'ARROWS'.length; i++)
                      Transform.translate(
                        offset: Offset(
                            0,
                            -18 *
                                math.max(
                                    0,
                                    math.sin((t * 1.6 - i * 0.09) *
                                            math.pi /
                                            0.5) /
                                        1.0)),
                        child: Opacity(
                          opacity: ((t - 0.32 - i * 0.05) * 6)
                              .clamp(0.0, 1.0),
                          child: Text(
                            'ARROWS'[i],
                            style: AppTheme.display(44,
                                color: AppTheme.ink),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: ((t - 0.72) * 4).clamp(0.0, 1.0),
                  child: Text('tap · slide · clear',
                      style: AppTheme.body(16, color: AppTheme.inkSoft)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    final p = Paint()
      ..color = AppTheme.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final dirs = [
      const Offset(0, -1), // up
      const Offset(0.866, 0.5), // lower right
      const Offset(-0.866, 0.5), // lower left
    ];
    for (int i = 0; i < 3; i++) {
      // staggered grow-in
      final local = ((t - i * 0.12) / 0.5).clamp(0.0, 1.0);
      final ease = Curves.easeOutBack.transform(local);
      final dir = dirs[i];
      final start = c + dir * (r * 0.12);
      final end = c + dir * (r * ease);
      if (ease <= 0.01) continue;
      canvas.drawLine(start, end, p);
      // arrowhead
      final ang = math.atan2(dir.dy, dir.dx);
      final head = Path()
        ..moveTo(0, 0)
        ..lineTo(-13, 8)
        ..lineTo(-13, -8)
        ..close;
      canvas.save();
      canvas.translate(end.dx, end.dy);
      canvas.rotate(ang);
      canvas.drawPath(head, Paint()..color = AppTheme.ink);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.t != t;
}
