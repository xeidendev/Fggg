import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_puzzle/core/engine.dart';
import 'package:arrow_puzzle/core/levels_data.dart';
import 'package:arrow_puzzle/game/board_transform.dart';

/// v5.0 regression suite for the FATAL tap bug.
///
/// The old code mapped taps with `scale = ortho*2 / boardHeight` while the
/// painter drew with `scale = max(ortho*2/width, ortho*2/height)`. On any
/// portrait phone those differ (~2.2x on 1080x2400), so taps away from the
/// board centre activated the WRONG arrow. Both sides now share
/// BoardTransform — these tests prove paint and tap can never diverge again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Levels.load(() => rootBundle.loadString('assets/levels/levels.json'));
  });

  group('BoardTransform parity', () {
    // Phones are always portrait; include a tablet-ish and near-square size.
    const sizes = [
      Size(360, 780),
      Size(390, 844),
      Size(412, 915),
      Size(768, 1024),
      Size(800, 360), // landscape safety check
    ];

    test('screenToWorld(worldToScreen(p)) == p for every board size', () {
      for (final size in sizes) {
        final def = Levels.instance[12]; // a mid-complexity level
        final eng = PuzzleEngine(def);
        final xform = BoardTransform(
          view: eng.computeView(size.width / size.height),
          boardSize: size,
        );
        // Sample the world bbox the painter can actually draw.
        double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
        for (final l in eng.lines) {
          for (final p in l.origin) {
            minX = math.min(minX, p.dx);
            maxX = math.max(maxX, p.dx);
            minY = math.min(minY, p.dy);
            maxY = math.max(maxY, p.dy);
          }
        }
        for (double x = minX; x <= maxX + 1e-9; x += (maxX - minX) / 10) {
          for (double y = minY; y <= maxY + 1e-9; y += (maxY - minY) / 10) {
            final p = Offset(x, y);
            final round = xform.screenToWorld(xform.worldToScreen(p));
            expect((round - p).distance, lessThan(1e-6),
                reason: 'round-trip failed at $p on $size');
          }
        }
      }
    });

    test('painter scale equals tap scale by construction', () {
      const size = Size(390, 844);
      final def = Levels.instance[40];
      final eng = PuzzleEngine(def);
      final xform = BoardTransform(
        view: eng.computeView(size.width / size.height),
        boardSize: size,
      );
      // The old painter scale — must be identical to xform.scale now.
      final worldToSize = xform.view.ortho * 2;
      final oldPainterScale =
          math.max(worldToSize / size.width, worldToSize / size.height);
      expect(xform.scale, moreOrLessEquals(oldPainterScale, epsilon: 1e-12));
      // The old (broken) tap scale differs on portrait — the fix must NOT
      // reproduce it.
      final oldTapScale = worldToSize / size.height;
      if (size.height != size.width) {
        expect(xform.scale == oldTapScale, isFalse,
            reason: 'tap scale must not use height only on portrait boards');
      }
    });
  });

  group('tap lands on the arrow you see', () {
    testWidgets('every painted arrow centre taps to its own line '
        '(sampled levels, portrait phone)', (tester) async {
      const size = Size(412, 915); // typical 2023 Android phone
      final rng = math.Random(42);
      final levelSample = List.generate(60, (_) => rng.nextInt(Levels.instance.total));

      int checked = 0;
      int exact = 0;
      for (final li in levelSample) {
        final def = Levels.instance[li];
        final eng = PuzzleEngine(def);
        final xform = BoardTransform(
          view: eng.computeView(size.width / size.height),
          boardSize: size,
        );
        for (final l in eng.lines) {
          // Sample a point near the middle of the visible stroke.
          final world = l.pointAtExtArc(l.length / 2);
          final screen = xform.worldToScreen(world);
          // The player taps 3 px off the stroke centre.
          final tapped = xform.screenToWorld(screen + const Offset(3, -2));
          final picked = eng.previewAt(tapped, slopRadius: 0.8);
          expect(picked, isNotNull,
              reason: 'level ${li + 1}: a tap right on line ${l.index} '
                  'must hit at least one line');
          // INVARIANT 1 (the fatal-bug killer): the line that fires must be
          // one of the lines actually under/near the finger. With the old
          // broken transform the mapped point drifted ~2.2x away from the
          // centre, so totally unrelated lines fired.
          final pickedD = eng.lines[picked!].distanceToWindow(tapped);
          final pickedHeadD = (tapped - eng.lines[picked].headPos).distance;
          // We injected a 3px offset, so "under the finger" means within
          // ~5px (plus head grab radius) of the mapped world point.
          final tol = xform.pxToWorld(5);
          expect(
            pickedD <= tol || pickedHeadD <= 0.45,
            isTrue,
            reason: 'level ${li + 1} line ${l.index}: tap on the drawn '
                'stroke at $screen fired line $picked which is nowhere '
                'near the finger (dist $pickedD)',
          );
          // INVARIANT 2: when NO other line is under the finger, the
          // original line must be picked exactly.
          var otherUnder = false;
          for (final o in eng.lines) {
            if (o.index == l.index || !o.isActive) continue;
            if (o.distanceToWindow(tapped) <= tol ||
                (tapped - o.headPos).distance <= 0.4) {
              otherUnder = true;
              break;
            }
          }
          if (!otherUnder) {
            expect(picked, l.index,
                reason: 'level ${li + 1}: unambiguous tap on line '
                    '${l.index} fired line $picked');
            exact++;
          }
          checked++;
        }
      }
      expect(checked, greaterThan(200));
      expect(exact, greaterThan(100));
    });

    test('launch-on-release fires exactly the highlighted line', () {
      final def = Levels.instance[8];
      final eng = PuzzleEngine(def);
      const size = Size(390, 844);
      final xform = BoardTransform(
        view: eng.computeView(size.width / size.height),
        boardSize: size,
      );
      final l = eng.lines.first;
      final screen = xform.worldToScreen(l.pointAtExtArc(l.length / 2));
      final idx = eng.previewAt(
        xform.screenToWorld(screen),
        slopRadius: xform.pxToWorld(34),
      );
      expect(idx, l.index);
      expect(eng.tapLine(idx!), isTrue);
      expect(eng.lines[l.index].state, LineState.flying);
      expect(eng.started, isTrue);
    });

    test('slop is pixel-derived: far-off taps do nothing', () {
      final def = Levels.instance[8];
      final eng = PuzzleEngine(def);
      const size = Size(390, 844);
      final xform = BoardTransform(
        view: eng.computeView(size.width / size.height),
        boardSize: size,
      );
      final far = xform.screenToWorld(const Offset(4, 4));
      expect(eng.tapAt(far, slopRadius: xform.pxToWorld(34)), isFalse);
      expect(eng.started, isFalse);
    });

    test('continueWithHearts restores play after a loss', () {
      final def = Levels.instance[4];
      final eng = PuzzleEngine(def);
      eng.hearts = 0;
      expect(eng.lost, isTrue);
      eng.continueWithHearts(3);
      expect(eng.hearts, 3);
      expect(eng.lost, isFalse);
      expect(eng.won, isFalse);
    });
  });
}
