import 'dart:math' as math;
import 'dart:typed_data';

import 'sfx_synth.dart';

/// Procedurally generated calm background music loop (pure Dart, no assets).
/// Gentle plucked arpeggio + soft bass over a I–vi–IV–V progression.
class MusicBank {
  static const int sr = SynthWav.sampleRate;
  static const double bpm = 92;
  static const int bars = 8;
  static const int beatsPerBar = 4;

  static const List<List<double>> _chords = [
    [261.63, 329.63, 392.0], // C
    [220.0, 261.63, 329.63], // Am
    [174.61, 220.0, 261.63], // F
    [196.0, 246.94, 293.66], // G
  ];

  static const List<double> _bass = [
    65.41, // C2
    55.0, // A1
    43.65, // F1
    49.0, // G1
  ];

  static Uint8List? _cached;

  static double _pluck(double t, double freq, double decay) {
    if (t < 0) return 0;
    final env = math.exp(-t * decay);
    return (math.sin(2 * math.pi * freq * t) * 0.7 +
            math.sin(2 * math.pi * freq * 2 * t) * 0.18 +
            math.sin(2 * math.pi * freq * 3 * t) * 0.08) *
        env;
  }

  /// Generates the loop (about 20s) once and caches it.
  static Future<Uint8List> loopWav() async {
    if (_cached != null) return _cached!;
    const beat = 60.0 / bpm;
    const totalBeats = bars * beatsPerBar;
    final n = (totalBeats * beat * sr).toInt();
    final out = List<double>.filled(n, 0);

    for (int b = 0; b < totalBeats; b++) {
      final chord = _chords[(b ~/ beatsPerBar) % _chords.length];
      final bass = _bass[(b ~/ beatsPerBar) % _bass.length];
      final startS = (b * beat * sr).toInt();

      // soft bass on every beat
      for (int i = 0; i < (beat * sr).toInt() && startS + i < n; i++) {
        final t = i / sr;
        out[startS + i] +=
            math.sin(2 * math.pi * bass * t) * math.exp(-t * 6) * 0.16;
      }

      // arpeggio: 8th notes, pattern up-down
      for (int h = 0; h < 2; h++) {
        final hs = ((b + h * 0.5) * beat * sr).toInt();
        final note = chord[(h + b) % 3];
        for (int i = 0; i < (beat * 0.9 * sr).toInt() && hs + i < n; i++) {
          final t = i / sr;
          out[hs + i] += _pluck(t, note, 5) * 0.12;
        }
      }

      // sparkle bell every 2 bars
      if (b % 8 == 4) {
        final bell = chord[2] * 2;
        for (int i = 0; i < (beat * 3 * sr).toInt() && startS + i < n; i++) {
          final t = i / sr;
          out[startS + i] +=
              math.sin(2 * math.pi * bell * t) * math.exp(-t * 3) * 0.045;
        }
      }
    }

    // gentle fade at loop edges for click-free wrap
    const fade = 800;
    for (int i = 0; i < fade; i++) {
      final g = i / fade;
      out[i] *= g;
      out[n - 1 - i] *= g;
    }

    _cached = SynthWav.encode(out);
    return _cached!;
  }
}
