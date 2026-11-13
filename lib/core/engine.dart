import 'dart:math' as math;
import 'dart:ui';

import 'levels_data.dart';

/// Physics arc step: Unity runs physics at 0.02s and lines move at 20 u/s
/// => the head advances 0.4 world units per physics tick. Collision checks are
/// done at these discrete arc positions for exact parity.
const double kPhysicsStepArc = 0.4;

const double kHeadRadius = 0.2;
const double kBodyHalfThickness = 0.1; // thickness 0.2
const double kBodyExtra = 0.2; // extraLenght (end caps)

enum LineState { idle, flying, reversing, cleared }

class TapSlop {
  /// Maximum world-unit slop for accepting a tap near a line. The screen
  /// passes a pixel-scaled radius (see PuzzleEngine.previewAt); this is the
  /// fallback used by pure world-space callers (tests, solver).
  static const double radius = 0.9;

  /// Never accept taps closer than this many world units to a line, no
  /// matter how zoomed-out the board is — keeps parallel lines separable.
  static const double minRadius = 0.4;

  /// Direct-hit band: inside this distance the tap is considered to be ON
  /// the stroke and wins over anything that only falls within the slop.
  static const double directHit = 0.16;

  /// Arrowhead grab radius (world units): the head triangle is the most
  /// salient visual part of an arrow, so tapping on/near a head must pick
  /// that line even where another stroke crosses under the finger.
  static const double headRadius = 0.35;
}

/// Runtime state of one line: a constant-length window sliding along the
/// original polyline extended by an infinite ray from its end.
class LineRuntime {
  LineRuntime(this.def, this.index)
      : origin = _dedup(def.points),
        length = _polylineArc(_dedup(def.points)) {
    _cum = [0.0];
    for (int i = 0; i < origin.length - 1; i++) {
      final d = (origin[i + 1] - origin[i]).distance;
      _cum.add(_cum.last + d);
    }
    arc = length;
    s = 0;
    // ray direction: normalized last segment
    final last = origin[origin.length - 1];
    final prev = origin[origin.length - 2];
    final dir = last - prev;
    final dl = dir.distance;
    rayDir = dl < 1e-9 ? const Offset(1, 0) : dir / dl;
    _extCum = [..._cum];
    _extPts = [...origin];
  }

  final LevelLine def;
  final int index;
  final List<Offset> origin; // deduped polyline (world space)
  final double length; // total arc of the original polyline (L0)

  late double arc; // == length; head travels `arc` along the ray
  late double s; // window start arc (tail position along extPath)
  late Offset rayDir;
  LineState state = LineState.idle;
  bool flashRed = false;

  // extended path: origin points + ray extension, with cumulative arcs
  late List<double> _cum;
  late List<Offset> _extPts;
  late List<double> _extCum;

  static List<Offset> _dedup(List<Offset> pts) {
    final out = <Offset>[pts.first];
    for (int i = 1; i < pts.length; i++) {
      if ((pts[i] - out.last).distance > 1e-6) out.add(pts[i]);
    }
    return out;
  }

  static double _polylineArc(List<Offset> pts) {
    double a = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      a += (pts[i + 1] - pts[i]).distance;
    }
    return a;
  }

  double get totalArc => arc;
  double get headArc => s + length;

  /// Ensure extended path covers [0, headArc].
  void _extendTo(double need) {
    while (_extCum.last < need) {
      final lastPt = _extPts.last;
      final next = lastPt + rayDir;
      _extPts.add(next);
      _extCum.add(_extCum.last + rayDir.distance);
    }
  }

  Offset pointAtExtArc(double a) {
    if (a <= 0) return _extPts.first;
    _extendTo(a + kPhysicsStepArc);
    int lo = 0, hi = _extCum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_extCum[mid] < a) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = math.max(1, lo);
    final a0 = _extCum[i - 1], a1 = _extCum[i];
    final t = a1 - a0 < 1e-9 ? 0.0 : (a - a0) / (a1 - a0);
    return Offset.lerp(_extPts[i - 1], _extPts[i], t)!;
  }

  Offset get headPos => pointAtExtArc(headArc);
  Offset get tailPos => pointAtExtArc(s);

  /// Visible window points (tail..head clipped along extPath).
  List<Offset> windowPoints() {
    _extendTo(headArc + kPhysicsStepArc);
    final pts = <Offset>[];
    final double a0 = s, a1 = headArc;
    pts.add(pointAtExtArc(a0));
    for (int i = 0; i < _extCum.length; i++) {
      if (_extCum[i] > a0 + 1e-6 && _extCum[i] < a1 - 1e-6) {
        pts.add(_extPts[i]);
      }
    }
    pts.add(pointAtExtArc(a1));
    return pts;
  }

  /// Body segments of the window (for collision checks by other heads).
  List<List<Offset>> windowSegments() {
    final pts = windowPoints();
    final segs = <List<Offset>>[];
    for (int i = 0; i < pts.length - 1; i++) {
      segs.add([pts[i], pts[i + 1]]);
    }
    return segs;
  }

  bool get isActive => state != LineState.cleared;

  void startFlight() {
    if (state == LineState.idle) {
      state = LineState.flying;
      flashRed = false;
    }
  }

  void reverse() {
    state = LineState.reversing;
  }

  /// Advance physics. Returns collision partner index or null.
  int? tick(double dt, List<LineRuntime> all) {
    if (state == LineState.cleared || state == LineState.idle) return null;
    if (state == LineState.flying) {
      double target = math.min(s + math.max(dt, 0) * def.speed, arc);
      int? hit;
      while (s < target - 1e-9) {
        final step = math.min(kPhysicsStepArc, target - s);
        s += step;
        if (s >= arc - 1e-9) {
          s = arc;
          state = LineState.cleared;
          return null;
        }
        hit = _checkCollisions(all);
        if (hit != null) {
          state = LineState.reversing;
          flashRed = true;
          return hit;
        }
      }
      s = target;
      return null;
    } else {
      // reversing: retreat window to 0
      s -= math.max(dt, 0) * def.speed;
      if (s <= 0) {
        s = 0;
        state = LineState.idle;
        flashRed = false;
      }
      return null;
    }
  }

  int? _checkCollisions(List<LineRuntime> all) {
    final head = headPos;
    for (final other in all) {
      if (other.index == index || !other.isActive) continue;
      // head vs head
      final oh = other.headPos;
      if ((head - oh).distance < 2 * kHeadRadius) return other.index;
      // head vs other body boxes
      final segs = other.windowSegments();
      for (final seg in segs) {
        if (circleHitsBox(head, kHeadRadius, seg[0], seg[1])) {
          return other.index;
        }
      }
    }
    return null;
  }

  /// Unity BoxCollider2D is centered on the segment midpoint:
  /// half-extents = (len/2 + extra, thickness/2). The circle must be
  /// projected against that center — not the segment start.
  static bool circleHitsBox(Offset c, double r, Offset a, Offset b) {
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final dir = b - a;
    final len = dir.distance;
    if (len < 1e-9) return (c - center).distance < r;
    final d = dir / len;
    final nrm = Offset(-d.dy, d.dx);
    final rel = c - center;
    final along = rel.dx * d.dx + rel.dy * d.dy;
    final perp = rel.dx * nrm.dx + rel.dy * nrm.dy;
    final halfLen = len / 2 + kBodyExtra;
    const halfT = kBodyHalfThickness;
    final dx = (along.abs() - halfLen).clamp(0.0, double.infinity);
    final dy = (perp.abs() - halfT).clamp(0.0, double.infinity);
    return dx * dx + dy * dy < r * r;
  }

  /// Distance from point p to this line's visible window (for tap picking).
  double distanceToWindow(Offset p) {
    final pts = windowPoints();
    double best = double.infinity;
    for (int i = 0; i < pts.length - 1; i++) {
      best = math.min(best, _distToSeg(p, pts[i], pts[i + 1]));
    }
    return best;
  }

  static double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 < 1e-9) return (p - a).distance;
    double t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  LineRuntime copyOf(int newIndex) {
    final c = LineRuntime(def, newIndex);
    c.s = s;
    c.state = state;
    c.flashRed = flashRed;
    c.arc = arc;
    return c;
  }
}

class PuzzleEngine {
  PuzzleEngine(this.def,
      {this.onCollide, this.onClear, this.onLaunch, int? idx})
      : lines = [
          for (int i = 0; i < def.lines.length; i++) LineRuntime(def.lines[i], i),
        ],
        levelIndex = idx ?? 0;

  final LevelDef def;
  final int levelIndex;
  final List<LineRuntime> lines;
  final void Function(int lineIndex, Offset at)? onCollide;
  final void Function(int lineIndex, Offset at)? onClear;
  final void Function(int lineIndex)? onLaunch;

  int hearts = 5;
  int get maxHearts => 5;
  int get remaining => lines.where((l) => l.isActive).length;
  bool get won => remaining == 0;
  bool get lost => hearts <= 0;
  double elapsed = 0;
  bool started = false; // timer starts on first tap
  Set<int> _reported = <int>{};

  /// Which line would a tap at [world] launch right now? Returns the index
  /// of the best-matching tappable (idle) line, or null.
  ///
  /// Three-pass picking:
  ///   1. direct hit — tap on a stroke (d <= directHit) or on an arrowhead
  ///      (headD <= headRadius). Nearest wins. This tier exists so a tap
  ///      directly on the big head triangle can never be stolen by another
  ///      stroke that merely crosses under the finger.
  ///   2. slop       — distance <= max(slopRadius, TapSlop.minRadius);
  ///                   nearest wins; the caller passes a pixel-derived
  ///                   radius so the same physical finger size works at
  ///                   every zoom level.
  /// Where several strokes genuinely overlap under the finger (crossings),
  /// the nearest one wins — the picked line is always one of the lines the
  /// player can actually see under their finger.
  int? previewAt(Offset world, {double? slopRadius}) {
    if (won || lost) return null;
    final slop = math.max(slopRadius ?? TapSlop.radius, TapSlop.minRadius);

    LineRuntime? direct;
    double directD = double.infinity;
    LineRuntime? near;
    double nearD = slop;
    for (final l in lines) {
      if (!l.isActive || l.state != LineState.idle) continue;
      final d = l.distanceToWindow(world);
      final headD = (world - l.headPos).distance;
      final onHead = headD <= TapSlop.headRadius;
      if ((d <= TapSlop.directHit || onHead)) {
        final score = math.min(d, headD);
        if (score <= directD) {
          directD = score;
          direct = l;
        }
      }
      if (d <= nearD) {
        nearD = d;
        near = l;
      }
    }
    final best = direct ?? near;
    return best?.index;
  }

  /// Launch the line with [index] if it exists and is idle. Returns true
  /// when the line was launched.
  bool tapLine(int index) {
    if (won || lost || index < 0 || index >= lines.length) return false;
    final l = lines[index];
    if (!l.isActive || l.state != LineState.idle) return false;
    l.startFlight();
    started = true;
    onLaunch?.call(l.index);
    return true;
  }

  /// Convenience: pick + launch in one call. [slopRadius] is in world units
  /// (derive from pixels with BoardTransform.pxToWorld for touch input).
  bool tapAt(Offset world, {double? slopRadius}) {
    final idx = previewAt(world, slopRadius: slopRadius);
    if (idx == null) return false;
    return tapLine(idx);
  }

  /// Rewarded-ad continue: refill hearts to at least [count] so play can
  /// resume where it stopped. Reversing lines simply keep retreating on the
  /// next tick.
  void continueWithHearts(int count) {
    hearts = math.max(hearts, count.clamp(1, maxHearts));
  }

  void tick(double dt) {
    if (won || lost) return;
    if (started) elapsed += dt;
    for (final l in lines) {
      final hit = l.tick(dt, lines);
      if (hit != null) {
        hearts--;
        onCollide?.call(l.index, l.headPos);
        if (lost) return;
      }
    }
    _fireClears();
  }

  void _fireClears() {
    for (final l in lines) {
      if (l.state == LineState.cleared && !_reported.contains(l.index)) {
        _reported.add(l.index);
        onClear?.call(l.index, l.headPos);
      }
    }
  }

  /// Viewport fitting (Unity CameraManager parity): padding 2, ortho clamp 5..50.
  ({Offset center, double ortho}) computeView(double aspect) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final l in lines) {
      for (final p in l.origin) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final w = (maxX - minX) + 4; // padding*2
    final h = (maxY - minY) + 4;
    double ortho = math.max(w / (2 * aspect), h / 2);
    ortho = ortho.clamp(5.0, 50.0);
    return (center: Offset(cx, cy), ortho: ortho);
  }

  /// Stars by time thresholds (30/45/60 defaults from LevelConfig).
  int stars() {
    final th = def.timeThresholds;
    if (elapsed <= th[0]) return 3;
    if (elapsed <= th[1]) return 2;
    if (elapsed <= th[2]) return 1;
    return 0;
  }

  bool get perfect => hearts == maxHearts;

  PuzzleEngine clone() {
    final c = PuzzleEngine(def,
        onCollide: onCollide, onClear: onClear, onLaunch: onLaunch, idx: levelIndex);
    c.hearts = hearts;
    c.elapsed = elapsed;
    c.started = started;
    for (int i = 0; i < lines.length; i++) {
      c.lines[i] = lines[i].copyOf(i);
    }
    final rep = Set<int>.from(_reported);
    c._reported = rep;
    return c;
  }
}
