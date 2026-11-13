import 'dart:convert' show jsonDecode;
import 'dart:ui';

/// One arrow line of a level.
class LevelLine {
  const LevelLine({
    required this.points,
    this.speed = 20,
    this.width = 0.1,
    this.thickness = 0.2,
    this.headScale = 0.45,
  });

  final List<Offset> points;
  final double speed;
  final double width; // LineRenderer widthMultiplier
  final double thickness; // BoxCollider2D thickness
  final double headScale; // triangle sprite scale

  factory LevelLine.fromJson(Map<String, dynamic> j) {
    return LevelLine(
      points: [
        for (final p in j['points'] as List<dynamic>)
          Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
      speed: (j['speed'] as num?)?.toDouble() ?? 20,
    );
  }
}

/// A level: list of lines + star time thresholds.
class LevelDef {
  const LevelDef({
    required this.index,
    required this.lines,
    this.timeThresholds = const [30, 45, 60],
    this.winCoins = 10,
  });

  final int index; // 0-based
  final List<LevelLine> lines;
  final List<double> timeThresholds;
  final int winCoins;

  static List<double> _thresholdsFor(int lineCount) {
    // Scale star thresholds with workload; tuned so an attentive player can
    // still 3-star early levels with the original 30/45/60 feel.
    if (lineCount <= 6) return const [30, 45, 60];
    if (lineCount <= 12) return const [40, 60, 90];
    if (lineCount <= 17) return const [55, 85, 120];
    return const [70, 105, 150];
  }

  factory LevelDef.fromJson(Map<String, dynamic> j, int index) {
    final lines = [
      for (final l in j['lines'] as List<dynamic>) LevelLine.fromJson(l),
    ];
    return LevelDef(
      index: index,
      lines: lines,
      timeThresholds: _thresholdsFor(lines.length),
      winCoins: 10,
    );
  }
}

/// Loaded once at startup from the bundled JSON asset.
class Levels {
  Levels._(this.all);

  final List<LevelDef> all;

  int get total => all.length;

  LevelDef operator [](int i) => all[i];

  static Levels? _instance;
  static Levels get instance => _instance!;

  static bool get ready => _instance != null;

  static Future<Levels> load(Future<String> Function() readAsset) async {
    final raw = await readAsset();
    final data = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final defs = <LevelDef>[
      for (int i = 0; i < data.length; i++) LevelDef.fromJson(data[i], i),
    ];
    _instance = Levels._(defs);
    return _instance!;
  }
}
