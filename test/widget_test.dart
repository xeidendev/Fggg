// App sanity tests: level bank integrity, tap disambiguation (regression for
// "clicking one arrow triggers another"), and the win fanfare audio blob.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_puzzle/core/engine.dart';
import 'package:arrow_puzzle/core/levels_data.dart';
import 'package:arrow_puzzle/core/sfx_synth.dart';

int _wavSamples(Uint8List wav) {
  // data chunk: find 'data' marker, read little-endian u32 size after it
  for (int i = 0; i < wav.length - 8; i++) {
    if (wav[i] == 0x64 && wav[i + 1] == 0x61 && wav[i + 2] == 0x74 && wav[i + 3] == 0x61) {
      return wav[i + 4] | (wav[i + 5] << 8) | (wav[i + 6] << 16) | (wav[i + 7] << 24);
    }
  }
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Levels.load(() => rootBundle.loadString('assets/levels/levels.json'));
  });

  test('level bank ships 1000 solvable-ready levels', () {
    expect(Levels.instance.total, 1000);
    for (int i = 0; i < Levels.instance.total; i++) {
      final def = Levels.instance[i];
      expect(def.index, i, reason: 'level index must match position at $i');
      expect(def.lines.length, greaterThanOrEqualTo(3));
      for (final l in def.lines) {
        expect(l.points.length, greaterThanOrEqualTo(2));
        expect(l.speed, greaterThan(0));
      }
    }
  });

  test('tap near a line activates exactly that line, never a neighbour', () {
    final eng = PuzzleEngine(Levels.instance[0]);
    int checked = 0;
    for (final target in eng.lines) {
      // find an unambiguous tap point on this line's visible window:
      // the target must be strictly nearer than every other idle line
      Offset? tap;
      for (final f in [0.15, 0.3, 0.5, 0.7, 0.85]) {
        final p = target.pointAtExtArc(target.length * f);
        double bestOther = double.infinity;
        for (final o in eng.lines) {
          if (identical(o, target) ||
              !o.isActive ||
              o.state != LineState.idle) {
            continue;
          }
          bestOther = math.min(bestOther, o.distanceToWindow(p));
        }
        if (target.distanceToWindow(p) + 0.3 < bestOther) {
          tap = p + const Offset(0.05, 0.05);
          break;
        }
      }
      if (tap == null) continue; // line is fully overlapped: skip
      checked++;
      final flyingBefore =
          eng.lines.where((l) => l.state == LineState.flying).length;
      expect(eng.tapAt(tap), isTrue,
          reason: 'tap on line ${target.index} body must be accepted');
      expect(target.state, LineState.flying,
          reason: 'line ${target.index} must be the one activated');
      expect(eng.lines.where((l) => l.state == LineState.flying).length,
          flyingBefore + 1,
          reason: 'exactly one line may activate per tap');
    }
    expect(checked, greaterThanOrEqualTo(2),
        reason: 'level 1 must offer enough isolated tap points');
  });

  test('win fanfare is a full-length valid WAV (~4.8s, 16-bit mono)', () {
    final wav = SfxBank.get('winfanfare');
    expect(wav.length, greaterThan(300000)); // 4.8s * 44100 * 2 bytes ≈ 423KB
    final dataBytes = _wavSamples(wav);
    expect(dataBytes, 4.8 * 44100 * 2);
    // cached: same instance returned
    expect(identical(wav, SfxBank.get('winfanfare')), isTrue);
  });

  test('synth bank renders every UI sound without clipping to silence', () {
    for (final name in ['star', 'coin', 'whoosh', 'perfect', 'unlock', 'pop', 'heart', 'count']) {
      final wav = SfxBank.get(name);
      expect(wav.length, greaterThan(1000), reason: '$name too short');
      final samples = _wavSamples(wav);
      expect(samples, greaterThan(0), reason: '$name has no data');
    }
  });
}
