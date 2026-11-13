import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/theme.dart';
import 'board_transform.dart';
import 'fx.dart';

/// Draws the puzzle board: lines, flight trails, heads, fx, vignette.
///
/// v5.0: receives the shared BoardTransform so what you see and what you
/// tap can never diverge (the old tap path recomputed a different scale).
class ArrowsPainter extends CustomPainter {
  ArrowsPainter({
    required this.engine,
    required this.fx,
    required this.theme,
    required this.xform,
    required this.time,
    this.hintIndex,
    this.previewIndex,
    this.dimmed = false,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final PuzzleEngine engine;
  final FxSystem fx;
  final LineTheme theme;
  final BoardTransform xform;
  final double time;
  final int? hintIndex;

  /// Line highlighted while the finger is down — the exact line that will
  /// launch when the finger lifts. Null when no line is under the finger.
  final int? previewIndex;

  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final worldToScreen = xform.worldToScreen;
    final scale = xform.scale;

    final shake = fx.shakeOffset();
    canvas.save();
    canvas.translate(shake.dx, shake.dy);

    if (dimmed) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x55000000));
    }

    if (theme.glow) {
      // neon: draw soft glow underlay
      final glow = Paint()
        ..color = theme.line.withAlpha(90)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.34 / scale
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      for (final l in engine.lines) {
        if (l.state == LineState.cleared) continue;
        final pts = l.windowPoints().map(worldToScreen).toList();
        if (pts.length < 2) continue;
        canvas.drawPath(_pathThrough(pts), glow);
      }
    }

    // reversing (red) lines under everything else
    for (final l in engine.lines) {
      if (l.state != LineState.reversing) continue;
      _drawLine(canvas, l, worldToScreen, scale,
          color: AppTheme.red, pulse: 0);
    }

    for (final l in engine.lines) {
      if (l.state == LineState.cleared || l.state == LineState.reversing) {
        continue;
      }
      final hintPulse = hintIndex == l.index
          ? (0.5 + 0.5 * math.sin(time * 6))
          : 0.0;
      final isPreview = previewIndex == l.index;
      _drawLine(canvas, l, worldToScreen, scale,
          color: theme.line, pulse: hintPulse, preview: isPreview);
      _drawHead(canvas, l, worldToScreen, scale);
    }

    _drawFx(canvas, worldToScreen, scale);
    _drawVignette(canvas, size);
    canvas.restore();
  }

  Path _pathThrough(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }

  void _drawLine(
    Canvas canvas,
    LineRuntime l,
    Offset Function(Offset) w2s,
    double scale, {
    required Color color,
    required double pulse,
    bool preview = false,
  }) {
    final pts = l.windowPoints().map(w2s).toList();
    if (pts.length < 2) return;

    // Press-preview: white halo under the line so the player can see exactly
    // which arrow will fire when the finger lifts.
    if (preview) {
      final under = Paint()
        ..color = Colors.white.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 0.5 / scale;
      canvas.drawPath(_pathThrough(pts), under);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 0.1 / scale;
    canvas.drawPath(_pathThrough(pts), paint);

    if (pulse > 0) {
      final halo = Paint()
        ..color = AppTheme.gold.withAlpha((110 * pulse).toInt())
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (0.1 + 0.22 * pulse) / scale;
      canvas.drawPath(_pathThrough(pts), halo);
    }

    // flight trail: fading polyline behind the head while flying
    if (l.state == LineState.flying) {
      final head = w2s(l.headPos);
      final trailPaint = Paint()
        ..color = color.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.16 / scale
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawLine(w2s(l.tailPos), head, trailPaint);
    }
  }

  void _drawHead(
    Canvas canvas,
    LineRuntime l,
    Offset Function(Offset) w2s,
    double scale,
  ) {
    final head = w2s(l.headPos);
    final prev = w2s(l.pointAtExtArc(math.max(0, l.headArc - 0.25)));
    final dir = (head - prev);
    final ang = math.atan2(dir.dy, dir.dx);
    final s = 0.45 / scale;

    final flying = l.state == LineState.flying;
    final pulse = flying ? 1 + 0.08 * math.sin(time * 20) : 1.0;

    final tri = Path()
      ..moveTo(0.62, 0)
      ..lineTo(-0.38, 0.52)
      ..lineTo(-0.38, -0.52)
      ..close;

    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(ang);
    canvas.scale(s * pulse, s * pulse);
    if (theme.glow) {
      canvas.drawShadow(tri, theme.head, 2, true);
    }
    canvas.drawPaintWrapped(tri, l.flashRed ? AppTheme.red : theme.head);
    canvas.restore();
  }

  void _drawFx(
    Canvas canvas,
    Offset Function(Offset) w2s,
    double scale,
  ) {
    for (final p in fx.particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final sp = w2s(p.pos);
      switch (p.kind) {
        case FxKind.ripple:
          final paint = Paint()
            ..color = p.color.withAlpha((p.color.alpha * t).toInt())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.05 / scale;
          canvas.drawCircle(sp, p.size / scale, paint);
          break;
        case FxKind.shockwave:
          final paint = Paint()
            ..color = p.color.withAlpha((p.color.alpha * t).toInt())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.1 / scale;
          canvas.drawCircle(sp, p.size / scale, paint);
          break;
        case FxKind.spark:
          final paint = Paint()..color = p.color.withAlpha((255 * t).toInt());
          canvas.drawCircle(sp, p.size / scale, paint);
          break;
        case FxKind.coin:
          final paint = Paint()..color = p.color;
          canvas.drawCircle(sp, p.size / scale, paint);
          final rim = Paint()
            ..color = const Color(0xFFB27E00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.03 / scale;
          canvas.drawCircle(sp, p.size / scale, rim);
          break;
        default:
          break;
      }
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    if (fx.vignette <= 0.01) return;
    final a = (fx.vignette * 120).toInt().clamp(0, 160);
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        rect.longestSide * 0.75,
        [const Color(0x00000000), Color.fromARGB(a, 210, 53, 47)],
      );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant ArrowsPainter oldDelegate) => true;
}

extension _TriPaint on Canvas {
  void drawPaintWrapped(Path tri, Color color) {
    drawPath(tri, Paint()..color = color);
  }
}
