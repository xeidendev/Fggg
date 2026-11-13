import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_puzzle/core/engine.dart';
import 'package:arrow_puzzle/core/levels_data.dart';
import 'package:arrow_puzzle/core/solver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Levels.load(() => rootBundle.loadString('assets/levels/levels.json'));
  });

  group('engine mechanics', () {
    test('window keeps constant length while flying', () {
      final eng = PuzzleEngine(Levels.instance[0]);
      final l = eng.lines[0];
      l.startFlight();
      for (int i = 0; i < 30; i++) {
        eng.tick(1 / 60);
        if (!l.isActive) break;
        final pts = l.windowPoints();
        double arc = 0;
        for (int k = 0; k < pts.length - 1; k++) {
          arc += (pts[k + 1] - pts[k]).distance;
        }
        expect(arc, moreOrLessEquals(l.length, epsilon: 0.02),
            reason: 'window length must stay constant at tick $i');
      }
    });

    test('tap with slop activates the nearest line', () {
      final eng = PuzzleEngine(Levels.instance[0]);
      // tap near (but clearly closest to) line 0 of L1
      final mid = eng.lines[0].pointAtExtArc(eng.lines[0].length / 2);
      final offsetTap = mid + const Offset(0.3, 0.0);
      expect(eng.tapAt(offsetTap), isTrue);
      expect(eng.lines[0].state, LineState.flying);
    });

    test('tap far from any line does nothing', () {
      final eng = PuzzleEngine(Levels.instance[0]);
      final far = eng.lines[0].pointAtExtArc(0) + const Offset(50, 50);
      expect(eng.tapAt(far), isFalse);
      expect(eng.started, isFalse);
    });

    test('level 1 completes with zero collisions when fired in order', () {
      final eng = PuzzleEngine(Levels.instance[0]);
      for (final l in eng.lines) {
        l.startFlight();
        int guard = 0;
        while (l.state == LineState.flying && guard++ < 5000) {
          eng.tick(1 / 60);
        }
        expect(l.state, LineState.cleared);
      }
      expect(eng.won, isTrue);
      expect(eng.hearts, 5);
    });

    test('colliding line loses a heart and reverses', () {
      // synthetic: horizontal line flying right into a vertical wall
      const wall = LevelLine(points: [
        Offset(0, 3),
        Offset(0, -3),
      ]);
      const flyer = LevelLine(points: [
        Offset(-5, 0),
        Offset(-2, 0),
      ]);
      const def = LevelDef(index: 0, lines: [wall, flyer]);
      final eng = PuzzleEngine(def);
      eng.tapAt(const Offset(-3.5, 0));
      int guard = 0;
      while (!eng.lost && guard++ < 10000) {
        eng.tick(1 / 60);
        if (eng.lines[1].state == LineState.reversing) break;
      }
      expect(eng.lines[1].state, LineState.reversing);
      expect(eng.hearts, 4);
      // reverse returns to idle at origin
      guard = 0;
      while (eng.lines[1].state == LineState.reversing && guard++ < 5000) {
        eng.tick(1 / 60);
      }
      expect(eng.lines[1].state, LineState.idle);
      final head = eng.lines[1].headPos;
      expect(head.dx, moreOrLessEquals(-2.0, epsilon: 0.05));
    });

    test('idle lines never collide by themselves', () {
      final eng = PuzzleEngine(Levels.instance[8]); // dense level
      for (int i = 0; i < 300; i++) {
        eng.tick(1 / 60);
      }
      expect(eng.hearts, 5);
    });

    test('stars follow time thresholds', () {
      final def = Levels.instance[0];
      final eng = PuzzleEngine(def);
      eng.started = true;
      eng.elapsed = 10;
      expect(eng.stars(), 3);
      eng.elapsed = 35;
      expect(eng.stars(), 2);
      eng.elapsed = 50;
      expect(eng.stars(), 1);
      eng.elapsed = 90;
      expect(eng.stars(), 0);
    });

    test('computeView clamps orthographic size', () {
      final eng = PuzzleEngine(Levels.instance[0]);
      final v = eng.computeView(16 / 9);
      expect(v.ortho, greaterThanOrEqualTo(5.0));
      expect(v.ortho, lessThanOrEqualTo(50.0));
    });

    test('clone is a deep snapshot for lookahead sims', () {
      final eng = PuzzleEngine(Levels.instance[0]);
      eng.tapAt(eng.lines[0].pointAtExtArc(eng.lines[0].length / 2));
      eng.tick(0.05);
      final c = eng.clone();
      expect(c.lines[0].s, moreOrLessEquals(eng.lines[0].s, epsilon: 1e-9));
      // mutate clone, original untouched
      c.tick(0.2);
      expect(c.lines[0].s, isNot(equals(eng.lines[0].s)));
    });
  });

  group('solver', () {
    test('all 1000 levels are solvable', () {
      final levels = Levels.instance;
      expect(levels.total, 1000);
      final failures = <int>[];
      for (int i = 0; i < levels.total; i++) {
        final order = Solver.solve(levels[i]);
        if (order == null || order.length != levels[i].lines.length) {
          failures.add(i + 1);
        }
      }
      expect(failures, isEmpty, reason: 'unsolvable levels: $failures');
    }, timeout: const Timeout(Duration(minutes: 12)));

    test('original 10 levels keep their exact line counts', () {
      final counts = [3, 3, 4, 5, 16, 36, 12, 16, 24, 40];
      for (int i = 0; i < 10; i++) {
        expect(Levels.instance[i].lines.length, counts[i],
            reason: 'level ${i + 1} line count mismatch');
      }
    });
  });

  group('generated level layout (levels 11+)', () {
    // Every grid point belongs to at most one line: no crossings, no shared
    // points, no arrowhead resting on another line, no line flying over
    // its own body.
    List<Offset> cells(List<Offset> pts) {
      final out = <Offset>[pts.first];
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i], b = pts[i + 1];
        final n = (b - a).distance.round();
        for (int k = 1; k <= n; k++) {
          final c = Offset.lerp(a, b, k / n)!;
          out.add(Offset(c.dx.roundToDouble(), c.dy.roundToDouble()));
        }
      }
      return out;
    }

    test('no crossings or shared points', () {
      final bad = <int>[];
      for (int i = 10; i < Levels.instance.total; i++) {
        final seen = <Offset>{};
        for (final l in Levels.instance[i].lines) {
          for (final c in cells(l.points)) {
            if (!seen.add(c)) {
              bad.add(i + 1);
              break;
            }
          }
          if (bad.isNotEmpty && bad.last == i + 1) break;
        }
      }
      expect(bad, isEmpty, reason: 'levels with overlapping lines: $bad');
    });

    test('arrows never fly over their own body', () {
      final bad = <int>[];
      for (int i = 10; i < Levels.instance.total; i++) {
        for (final l in Levels.instance[i].lines) {
          final own = cells(l.points).toSet();
          final p = l.points;
          final d = p.last - p[p.length - 2];
          final dir = d / d.distance;
          final len = own.length - 1;
          for (int j = 1; j <= len; j++) {
            if (own.contains(p.last + dir * j.toDouble())) {
              bad.add(i + 1);
              break;
            }
          }
        }
      }
      expect(bad, isEmpty, reason: 'self-crossing arrows in levels: $bad');
    });

    test('no difficulty cliff after the 10 original levels', () {
      for (int i = 10; i < Levels.instance.total; i++) {
        expect(Levels.instance[i].lines.length, greaterThanOrEqualTo(12),
            reason: 'level ${i + 1} is too sparse');
      }
    });
  });

  group('bot (zero-collision full clear)', () {
    // first 20 + every 100th level: bot must win with all 5 hearts intact
    final sample = <int>[
      for (int i = 1; i <= 20; i++) i,
      for (int i = 100; i <= 1000; i += 100) i,
    ];

    for (final lvl in sample) {
      test('bot clears level $lvl with 5 hearts', () {
        final eng = PuzzleEngine(Levels.instance[lvl - 1], idx: lvl - 1);
        Bot.play(eng);
        expect(eng.won, isTrue, reason: 'bot failed to clear level $lvl');
        expect(eng.hearts, 5, reason: 'bot lost hearts on level $lvl');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}
