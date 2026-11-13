import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted game state: progress, coins, stars, settings, cosmetic themes.
class GameSave {
  GameSave._(this._prefs);

  final SharedPreferences _prefs;

  static GameSave? _instance;
  static GameSave get instance => _instance!;

  static Future<GameSave> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = GameSave._(prefs);
    return _instance!;
  }

  // ---- progress ----
  int get maxLevel => _prefs.getInt('maxLevel') ?? 1; // 1-based unlocked
  void setMaxLevel(int v) => _prefs.setInt('maxLevel', v);

  int get coins => _prefs.getInt('coins') ?? 0;
  void setCoins(int v) => _prefs.setInt('coins', v);
  void addCoins(int v) => setCoins((coins + v).clamp(0, 999999));

  // stars per level (1-based level -> 0..3)
  Map<int, int> get _stars {
    final raw = _prefs.getString('stars');
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
      return m;
    } catch (_) {
      return {};
    }
  }

  int starsAt(int level1) => _stars[level1] ?? 0;

  void setStars(int level1, int stars) {
    final m = _stars;
    if (stars > (m[level1] ?? 0)) {
      m[level1] = stars;
      _prefs.setString(
          'stars', jsonEncode(m.map((k, v) => MapEntry('$k', v))));
    }
  }

  int get totalStars => _stars.values.fold(0, (a, b) => a + b);

  // ---- settings ----
  bool get soundOn => _prefs.getBool('soundOn') ?? true;
  void setSoundOn(bool v) => _prefs.setBool('soundOn', v);

  bool get musicOn => _prefs.getBool('musicOn') ?? true;
  void setMusicOn(bool v) => _prefs.setBool('musicOn', v);

  bool get hapticsOn => _prefs.getBool('hapticsOn') ?? true;
  void setHapticsOn(bool v) => _prefs.setBool('hapticsOn', v);

  // ---- monetisation (v5.0) ----
  /// "Remove ads" IAP. A paid purchase survives progress resets.
  bool get adsRemoved => _prefs.getBool('adsRemoved') ?? false;
  void setAdsRemoved(bool v) => _prefs.setBool('adsRemoved', v);

  /// Daily bonus: +40 coins once per calendar day (local time).
  static const int dailyBonusCoins = 40;

  bool get dailyBonusReady {
    final last = _prefs.getInt('lastDailyBonus') ?? 0;
    if (last == 0) return true;
    final lastDay = DateTime.fromMillisecondsSinceEpoch(last);
    final now = DateTime.now();
    return lastDay.year != now.year ||
        lastDay.month != now.month ||
        lastDay.day != now.day;
  }

  void claimDailyBonus() {
    _prefs.setInt('lastDailyBonus', DateTime.now().millisecondsSinceEpoch);
    addCoins(dailyBonusCoins);
  }

  /// Hours (ceil) until the next daily bonus — for the menu chip countdown.
  int hoursUntilDailyBonus() {
    final last = _prefs.getInt('lastDailyBonus') ?? 0;
    if (last == 0) return 0;
    final next = DateTime.fromMillisecondsSinceEpoch(last).add(const Duration(days: 1));
    final h = next.difference(DateTime.now()).inHours;
    return h < 0 ? 0 : h + 1;
  }

  // ---- cosmetics ----
  int get themeId => _prefs.getInt('themeId') ?? 0;
  void setThemeId(int v) => _prefs.setInt('themeId', v);

  List<int> get unlockedThemes {
    final raw = _prefs.getString('unlockedThemes');
    if (raw == null || raw.isEmpty) return const [0];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [0];
    }
  }

  void unlockTheme(int id) {
    final l = unlockedThemes.toList();
    if (!l.contains(id)) {
      l.add(id);
      _prefs.setString('unlockedThemes', jsonEncode(l));
    }
  }

  void resetAll() {
    _prefs.remove('maxLevel');
    _prefs.remove('coins');
    _prefs.remove('stars');
    _prefs.remove('themeId');
    _prefs.remove('unlockedThemes');
    _prefs.remove('lastDailyBonus');
    // NOTE: 'adsRemoved' intentionally survives — a paid purchase must
    // never be wiped by resetting game progress.
  }
}
