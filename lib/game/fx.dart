import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum FxKind { spark, confetti, ripple, coin, starTrail, shockwave }

class FxParticle {
  FxParticle({
    required this.kind,
    required this.pos,
    required this.vel,
    required this.life,
    required this.maxLife,
    required this.size,
    required this.color,
    this.spin = 0,
    this.rot = 0,
    this.gravity = 0,
    this.drag = 1,
    this.target,
  });

  final FxKind kind;
  Offset pos;
  Offset vel;
  double life;
  double maxLife;
  double size;
  Color color;
  double spin;
  double rot;
  double gravity;
  double drag;
  Offset? target;
}

/// World-space juice: bursts, confetti, ripples, coin flights, shake, vignette.
class FxSystem extends ChangeNotifier {
  final List<FxParticle> _particles = <FxParticle>[];
  final math.Random _rng = math.Random();

  double shake = 0;
  double vignette = 0;
  int _shakeSeed = 0;

  Iterable<FxParticle> get particles => _particles;
  bool get isEmpty => _particles.isEmpty && shake <= 0.001 && vignette <= 0.001;

  void tapRipple(Offset at) {
    _particles.add(FxParticle(
      kind: FxKind.ripple,
      pos: at,
      vel: Offset.zero,
      life: 0.35,
      maxLife: 0.35,
      size: 0.5,
      color: const Color(0x553A3633),
    ));
  }

  void clearBurst(Offset at, Color base) {
    for (int i = 0; i < 26; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = 2.5 + _rng.nextDouble() * 7;
      _particles.add(FxParticle(
        kind: FxKind.spark,
        pos: at,
        vel: Offset(math.cos(a) * sp, math.sin(a) * sp),
        life: 0.5 + _rng.nextDouble() * 0.35,
        maxLife: 0.85,
        size: 0.06 + _rng.nextDouble() * 0.1,
        color: _tint(base, _rng),
        gravity: 6,
        drag: 0.94,
      ));
    }
    _particles.add(FxParticle(
      kind: FxKind.shockwave,
      pos: at,
      vel: Offset.zero,
      life: 0.4,
      maxLife: 0.4,
      size: 0.4,
      color: base.withAlpha(160),
    ));
    notifyListeners();
  }

  void hitSparks(Offset at) {
    for (int i = 0; i < 18; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = 3 + _rng.nextDouble() * 8;
      _particles.add(FxParticle(
        kind: FxKind.spark,
        pos: at,
        vel: Offset(math.cos(a) * sp, math.sin(a) * sp),
        life: 0.35 + _rng.nextDouble() * 0.3,
        maxLife: 0.65,
        size: 0.05 + _rng.nextDouble() * 0.09,
        color: Color.lerp(
            const Color(0xFFD2352F), const Color(0xFFFFB199), _rng.nextDouble())!,
        gravity: 8,
        drag: 0.93,
      ));
    }
    shake = math.min(1.0, shake + 0.7);
    vignette = 1;
    _shakeSeed++;
    notifyListeners();
  }

  void coinFlight(Offset from, Offset to, {int count = 6}) {
    for (int i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = 1.5 + _rng.nextDouble() * 3;
      _particles.add(FxParticle(
        kind: FxKind.coin,
        pos: from,
        vel: Offset(math.cos(a) * sp, math.sin(a) * sp - 2),
        life: 0.9,
        maxLife: 0.9,
        size: 0.34,
        color: const Color(0xFFF6B51E),
        gravity: 2,
        drag: 0.9,
        target: to,
      ));
    }
    notifyListeners();
  }

  /// Rewarded continue: green heart-heal burst at the board center.
  void continueBurst(Offset at) {
    _particles.add(FxParticle(
      kind: FxKind.shockwave,
      pos: at,
      vel: Offset.zero,
      life: 0.6,
      maxLife: 0.6,
      size: 0.6,
      color: const Color(0xFF3DBB7D),
    ));
    for (int i = 0; i < 22; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = 2 + _rng.nextDouble() * 6;
      _particles.add(FxParticle(
        kind: FxKind.spark,
        pos: at,
        vel: Offset(math.cos(a) * sp, math.sin(a) * sp),
        life: 0.4 + _rng.nextDouble() * 0.4,
        maxLife: 0.8,
        size: 0.05 + _rng.nextDouble() * 0.08,
        color: Color.lerp(
            const Color(0xFF3DBB7D), const Color(0xFFB7F5D3), _rng.nextDouble())!,
        gravity: 4,
        drag: 0.93,
      ));
    }
    notifyListeners();
  }

  void starPop(Offset at) {
    for (int i = 0; i < 12; i++) {
      final a = -math.pi / 2 + (_rng.nextDouble() - 0.5) * 2.4;
      final sp = 3 + _rng.nextDouble() * 6;
      _particles.add(FxParticle(
        kind: FxKind.spark,
        pos: at,
        vel: Offset(math.cos(a) * sp, math.sin(a) * sp),
        life: 0.4 + _rng.nextDouble() * 0.3,
        maxLife: 0.7,
        size: 0.05 + _rng.nextDouble() * 0.08,
        color: const Color(0xFFF6B51E),
        gravity: 5,
        drag: 0.94,
      ));
    }
    notifyListeners();
  }

  /// Screen-space confetti is handled in the overlay (UI), not world fx.
  void tick(double dt) {
    if (shake > 0) {
      shake = math.max(0, shake - dt * 3.2);
    }
    if (vignette > 0) {
      vignette = math.max(0, vignette - dt * 2.4);
    }
    if (_particles.isEmpty) return;
    for (final p in _particles) {
      p.life -= dt;
      if (p.kind == FxKind.coin && p.target != null) {
        // homing flight to HUD coin position
        final to = p.target! - p.pos;
        final d = to.distance;
        if (d < 0.6 || p.life < 0.18) {
          p.vel = to * 9;
        } else {
          p.vel = p.vel * p.drag + to / d * 26 * dt;
        }
        p.pos = p.pos + p.vel * dt;
      } else if (p.kind == FxKind.ripple) {
        p.size += dt * 4.2;
      } else if (p.kind == FxKind.shockwave) {
        p.size += dt * 10;
      } else {
        p.vel = Offset(p.vel.dx * p.drag, p.vel.dy * p.drag + p.gravity * dt);
        p.pos = p.pos + p.vel * dt;
        p.rot += p.spin * dt;
      }
    }
    _particles.removeWhere((p) => p.life <= 0);
    notifyListeners();
  }

  Offset shakeOffset() {
    if (shake <= 0.001) return Offset.zero;
    final s = shake * shake * 0.16;
    final r = _rng;
    return Offset((r.nextDouble() - 0.5) * 2 * s, (r.nextDouble() - 0.5) * 2 * s);
  }

  int get seed => _shakeSeed;

  static Color _tint(Color base, math.Random rng) {
    final targets = [base, base, const Color(0xFFF6B51E), const Color(0xFF3DBB7D)];
    return targets[rng.nextInt(targets.length)];
  }
}
