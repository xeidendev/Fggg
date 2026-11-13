import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'music_bank.dart';
import 'sfx_synth.dart';

/// Central audio facade. Never throws — audio failures must never crash play.
class GameAudio {
  static const int _poolSize = 6;
  static final List<AudioPlayer> _pool = <AudioPlayer>[];
  static int _poolIdx = 0;
  static AudioPlayer? _music;
  // Dedicated player for the victory fanfare: mediaPlayer-mode audio can play
  // any length in full and, being separate, the SFX round-robin can never
  // stop() it mid-play (this was the bug where the win music cut off early).
  static AudioPlayer? _jingle;
  static int _jingleToken = 0;
  static bool _ready = false;
  static bool soundOn = true;
  static bool musicOn = true;

  static String _assetFor(String key) {
    switch (key) {
      case 'move':
        return 'audio/move.wav';
      case 'collide':
        return 'audio/collide.wav';
      case 'click':
        return 'audio/click.mp3';
      case 'coin':
        return 'audio/coin.wav';
      case 'win':
        return 'audio/win.mp3';
      case 'win2':
        return 'audio/win2.wav';
      case 'lose':
        return 'audio/lose.ogg';
      case 'confirm':
        return 'audio/confirm.mp3';
      case 'open':
        return 'audio/open.mp3';
      case 'close':
        return 'audio/close.wav';
      default:
        return 'audio/click.mp3';
    }
  }

  static Future<void> init({required bool sound, required bool music}) async {
    soundOn = sound;
    musicOn = music;
    if (_ready) return;
    try {
      for (int i = 0; i < _poolSize; i++) {
        final p = AudioPlayer(playerId: 'arrows_sfx_$i');
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      _ready = true;
    } catch (_) {
      _ready = _pool.isNotEmpty;
    }
  }

  static Source _source(String key) => AssetSource(_assetFor(key));

  static Future<void> play(String key) async {
    if (!_ready || !soundOn || _pool.isEmpty) return;
    try {
      final p = _pool[_poolIdx];
      _poolIdx = (_poolIdx + 1) % _pool.length;
      await p.stop();
      await p.setSource(_source(key));
      await p.resume();
    } catch (_) {}
  }

  /// Synthesized UI sounds: star, coin2, whoosh, perfect, unlock, pop, heart, count.
  static Future<void> playSynth(String name) async {
    if (!_ready || !soundOn || _pool.isEmpty) return;
    try {
      final bytes = SfxBank.get(name);
      final p = _pool[_poolIdx];
      _poolIdx = (_poolIdx + 1) % _pool.length;
      await p.stop();
      await p.setSourceBytes(bytes);
      await p.resume();
    } catch (_) {}
  }

  // ---- victory fanfare (dedicated full-length player) ----
  /// Plays the win fanfare to completion on its own media player and pauses
  /// the background music until the fanfare finishes. Never throws.
  static Future<void> playWinJingle() async {
    if (!_ready || !soundOn) return;
    final token = ++_jingleToken;
    const fanfareLen = 4.8;
    try {
      await pauseMusic();
      _jingle ??= AudioPlayer(playerId: 'arrows_win_jingle')
        ..setPlayerMode(PlayerMode.mediaPlayer);
      await _jingle!.setReleaseMode(ReleaseMode.stop);
      await _jingle!.setVolume(0.8);
      await _jingle!.stop();
      await _jingle!.setSourceBytes(SfxBank.get('winfanfare'));
      await _jingle!.resume();
    } catch (_) {}
    // Bring the calm BGM back once the celebration has finished.
    final resumeIn = (fanfareLen * 1000 + 500).toInt();
    Future.delayed(Duration(milliseconds: resumeIn), () async {
      if (token != _jingleToken) return; // a newer jingle superseded us
      if (musicOn) await startMusic();
    });
  }

  static Future<void> stopWinJingle() async {
    // Note: intentionally does NOT bump _jingleToken — the scheduled BGM
    // resume must still fire after stopping the fanfare early.
    try {
      await _jingle?.stop();
    } catch (_) {}
  }

  // ---- music ----
  static Future<void> startMusic() async {
    if (!musicOn) return;
    try {
      _music ??= AudioPlayer(playerId: 'arrows_music')
        ..setPlayerMode(PlayerMode.mediaPlayer);
      await _music!.setReleaseMode(ReleaseMode.loop);
      final bytes = await MusicBank.loopWav();
      await _music!.setVolume(0.14);
      await _music!.setSourceBytes(bytes);
      await _music!.resume();
    } catch (_) {}
  }

  static Future<void> pauseMusic() async {
    try {
      await _music?.pause();
    } catch (_) {}
  }

  static Future<void> applySettings({required bool sound, required bool music}) async {
    soundOn = sound;
    if (music != musicOn) {
      musicOn = music;
      if (musicOn) {
        await startMusic();
      } else {
        await pauseMusic();
      }
    } else {
      musicOn = music;
    }
  }

  static Future<void> dispose() async {
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
    try {
      await _music?.dispose();
    } catch (_) {}
    _music = null;
    try {
      await _jingle?.dispose();
    } catch (_) {}
    _jingle = null;
    _ready = false;
  }
}

/// Compact tone helper used by widgets for haptic-ish blips (kept for tests).
class SfxKeys {
  static const tap = 'click';
  static const confirm = 'confirm';
  static const open = 'open';
  static const close = 'close';
  static const move = 'move';
  static const collide = 'collide';
  static const win = 'win';
  static const lose = 'lose';
  static const coin = 'coin';

  static Uint8List? synth(String name) => SfxBank.get(name);
}
