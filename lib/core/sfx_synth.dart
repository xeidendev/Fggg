/// Tiny pure-Dart WAV synthesizer for UI effects that don't exist in the
/// original Unity asset set (star dings, coin, whoosh, perfect, unlock...).
library;
import 'dart:convert' show base64Encode;
import 'dart:math' as math;
import 'dart:typed_data';

class SynthWav {
  static const int sampleRate = 44100;

  /// Render mono f32 samples into a 16-bit PCM WAV byte blob.
  static Uint8List encode(List<double> samples) {
    final data = BytesBuilder();
    for (final s in samples) {
      final v = (s.clamp(-1.0, 1.0) * 32767).round();
      data.addByte(v & 0xff);
      data.addByte((v >> 8) & 0xff);
    }
    final pcm = data.takeBytes();
    final out = BytesBuilder();
    void str(String s) => out.add(s.codeUnits);
    void u32(int v) {
      out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    }

    void u16(int v) {
      out.add([v & 0xff, (v >> 8) & 0xff]);
    }

    str('RIFF');
    u32(36 + pcm.length);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(pcm.length);
    out.add(pcm);
    return out.takeBytes();
  }

  /// Build samples from named recipe.
  static List<double> render(String name) {
    switch (name) {
      case 'star':
        return _star();
      case 'coin':
        return _coin();
      case 'whoosh':
        return _whoosh();
      case 'perfect':
        return _perfect();
      case 'unlock':
        return _unlock();
      case 'pop':
        return _pop();
      case 'heart':
        return _heart();
      case 'count':
        return _count();
      default:
        return _pop();
    }
  }

  static double _env(int i, int n, double a, double r) {
    final t = i / n;
    final attack = a <= 0 ? 1.0 : math.min(1.0, t / a);
    final release = r <= 0 ? 1.0 : math.min(1.0, (1 - t) / r);
    return attack * release;
  }

  static List<double> _star() {
    final n = (sampleRate * 0.28).toInt();
    final out = List<double>.filled(n, 0);
    const freqs = [880.0, 1108.7, 1318.5];
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      double v = 0;
      for (int f = 0; f < freqs.length; f++) {
        final startT = f * 0.055;
        if (t >= startT) {
          final lt = t - startT;
          final env = math.exp(-lt * 14);
          v += math.sin(2 * math.pi * freqs[f] * lt) * env * (f == 2 ? 0.5 : 0.35);
        }
      }
      out[i] = v * 0.8;
    }
    return out;
  }

  static List<double> _coin() {
    final n = (sampleRate * 0.14).toInt();
    final out = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 26);
      final f = 1568 + t * 800;
      out[i] = (math.sin(2 * math.pi * f * t) * 0.6 +
              math.sin(2 * math.pi * f * 2 * t) * 0.2) *
          env;
    }
    return out;
  }

  static List<double> _whoosh() {
    final n = (sampleRate * 0.3).toInt();
    final out = List<double>.filled(n, 0);
    double lp = 0;
    final rng = math.Random(20260101);
    for (int i = 0; i < n; i++) {
      final t = i / n;
      final env = math.sin(math.pi * t);
      final white = rng.nextDouble() * 2 - 1;
      final cutoff = 0.08 + 0.5 * env;
      lp += (white - lp) * cutoff;
      out[i] = lp * env * 1.6;
    }
    return out;
  }

  static List<double> _perfect() {
    final n = (sampleRate * 0.55).toInt();
    final out = List<double>.filled(n, 0);
    const chord = [523.25, 659.25, 783.99, 1046.5];
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 4.5) * _env(i, n, 0.02, 0.25);
      double v = 0;
      for (int c = 0; c < chord.length; c++) {
        final st = c * 0.06;
        if (t >= st) {
          v += math.sin(2 * math.pi * chord[c] * (t - st)) *
              (1 - c * 0.12) *
              math.exp(-(t - st) * 5);
        }
      }
      out[i] = v * env * 0.7;
    }
    return out;
  }

  static List<double> _unlock() {
    final n = (sampleRate * 0.7).toInt();
    final out = List<double>.filled(n, 0);
    const notes = [392.0, 523.25, 659.25, 783.99, 1046.5];
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      double v = 0;
      for (int c = 0; c < notes.length; c++) {
        final st = c * 0.085;
        if (t >= st) {
          final lt = t - st;
          v += math.sin(2 * math.pi * notes[c] * lt) * math.exp(-lt * 6) * 0.4;
        }
      }
      out[i] = v * _env(i, n, 0.01, 0.3);
    }
    return out;
  }

  static List<double> _pop() {
    final n = (sampleRate * 0.09).toInt();
    final out = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 40);
      final f = 420 + 900 * t;
      out[i] = math.sin(2 * math.pi * f * t) * env * 0.7;
    }
    return out;
  }

  static List<double> _heart() {
    final n = (sampleRate * 0.25).toInt();
    final out = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 12);
      out[i] = math.sin(2 * math.pi * (196 + t * -60) * t) * env * 0.8;
    }
    return out;
  }

  static List<double> _count() {
    final n = (sampleRate * 0.06).toInt();
    final out = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 60);
      out[i] = math.sin(2 * math.pi * 1318 * t) * env * 0.5;
    }
    return out;
  }

  /// Full victory fanfare (~4.8s): rising brass stabs, held final chord,
  /// sparkle bells and a soft echo tail. Played on a dedicated media player
  /// so it always plays to the end.
  static List<double> winFanfare() {
    const dur = 4.8;
    final n = (sampleRate * dur).toInt();
    final out = List<double>.filled(n, 0);

    // brass-ish tone: sine + harmonics with slight detune shimmer
    void note(double freq, double start, double len, double vol,
        {double decay = 3.0, double vibrato = 0.0}) {
      final startI = (start * sampleRate).toInt();
      final lenI = (len * sampleRate).toInt();
      for (int i = 0; i < lenI; i++) {
        final idx = startI + i;
        if (idx < 0 || idx >= n) continue;
        final t = i / sampleRate;
        final attack = math.min(1.0, t / 0.012);
        final release = len - t < 0.25 ? (len - t) / 0.25 : 1.0;
        final env = attack * math.exp(-t * decay) * release;
        final vib = vibrato > 0
            ? 1.0 + vibrato * math.sin(2 * math.pi * 5.2 * t)
            : 1.0;
        final v = math.sin(2 * math.pi * freq * vib * t) * 0.62 +
            math.sin(2 * math.pi * freq * 2 * vib * t) * 0.22 +
            math.sin(2 * math.pi * freq * 3 * vib * t) * 0.10;
        out[idx] += v * env * vol;
      }
    }

    void chord(List<double> fs, double start, double len, double vol,
        {double decay = 3.0}) {
      for (final f in fs) {
        note(f, start, len, vol, decay: decay);
      }
    }

    // Section A — "ta-da-da-daa" rising stabs (C, F, G)
    chord([261.63, 329.63, 392.0], 0.00, 0.22, 0.30, decay: 9);
    chord([261.63, 329.63, 392.0], 0.22, 0.22, 0.30, decay: 9);
    chord([349.23, 440.00, 523.25], 0.44, 0.22, 0.30, decay: 9);
    chord([392.00, 493.88, 587.33], 0.66, 0.22, 0.30, decay: 9);

    // Section B — big held C major chord with vibrato + root pad
    const held = [523.25, 659.26, 783.99, 1046.50];
    for (int c = 0; c < held.length; c++) {
      note(held[c], 0.88 + c * 0.055, 2.35, 0.20 - c * 0.02,
          decay: 0.9, vibrato: 0.004);
    }
    note(130.81, 0.88, 2.3, 0.16, decay: 1.1); // C3 pad
    note(261.63, 0.88, 2.3, 0.10, decay: 1.1); // C4 pad

    // Section C — sparkle bells (C6 E6 G6 C7) near the end
    const bells = [1046.5, 1318.5, 1568.0, 2093.0];
    for (int b = 0; b < bells.length; b++) {
      note(bells[b], 3.15 + b * 0.13, 0.9, 0.16, decay: 6);
    }
    // answering low flourish
    chord([523.25, 659.26, 783.99], 3.95, 0.7, 0.16, decay: 4);

    // master fade + soft echo for warmth
    final echo = (0.117 * sampleRate).toInt();
    for (int i = n - 1; i >= 0; i--) {
      if (i >= echo) out[i] += out[i - echo] * 0.16;
    }
    final fadeStart = n - (sampleRate * 0.5).toInt();
    for (int i = fadeStart; i < n; i++) {
      out[i] *= (n - i) / (n - fadeStart);
    }
    for (int i = 0; i < n; i++) {
      out[i] = out[i].clamp(-1.0, 1.0) * 0.92;
    }
    return out;
  }
}

class SfxBank {
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, String> _b64 = {};

  static Uint8List get(String name) {
    if (name == 'winfanfare') {
      return _cache.putIfAbsent(
          name, () => SynthWav.encode(SynthWav.winFanfare()));
    }
    return _cache.putIfAbsent(name, () => SynthWav.encode(SynthWav.render(name)));
  }

  static String b64(String name) =>
      _b64.putIfAbsent(name, () => base64Encode(get(name)));
}
