
import 'package:flutter/material.dart';

/// Global visual identity: Fredoka typography, warm paper palette,
/// unlockable arrow color themes.
class AppTheme {
  static const Color paper = Color(0xFFF4EEE7);
  static const Color paperDark = Color(0xFFE9E1D7);
  static const Color ink = Color(0xFF3A3633);
  static const Color inkSoft = Color(0xFF6E655E);
  static const Color red = Color(0xFFD2352F);
  static const Color blue = Color(0xFF328BF3);
  static const Color gold = Color(0xFFF6B51E);
  static const Color green = Color(0xFF3DBB7D);
  static const Color purple = Color(0xFF8A5CF6);
  static const Color night = Color(0xFF241E33);
  static const Color white = Colors.white;

  static const pageBg = Color(0xFFF6F1EA);

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: pageBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        brightness: Brightness.light,
      ).copyWith(surface: pageBg),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Fredoka'),
    );
  }

  static TextTheme get text => const TextTheme();

  static TextStyle display(double size, {Color? color, FontWeight? w}) =>
      TextStyle(
        fontFamily: 'Fredoka',
        fontSize: size,
        fontWeight: w ?? FontWeight.w700,
        color: color ?? ink,
        height: 1.05,
      );

  static TextStyle title(double size, {Color? color}) => TextStyle(
        fontFamily: 'Fredoka',
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? ink,
      );

  static TextStyle body(double size, {Color? color, FontWeight? w}) =>
      TextStyle(
        fontFamily: 'Fredoka',
        fontSize: size,
        fontWeight: w ?? FontWeight.w500,
        color: color ?? ink,
      );
}

/// Unlockable line palettes.
class LineTheme {
  const LineTheme({
    required this.id,
    required this.name,
    required this.price,
    required this.line,
    required this.head,
    required this.bgTop,
    required this.bgBottom,
    this.glow = false,
  });

  final int id;
  final String name;
  final int price;
  final Color line;
  final Color head;
  final Color bgTop;
  final Color bgBottom;
  final bool glow;

  static const List<LineTheme> all = [
    LineTheme(
      id: 0,
      name: 'Classic',
      price: 0,
      line: Color(0xFF3A3633),
      head: Color(0xFF3A3633),
      bgTop: Color(0xFFF6F1EA),
      bgBottom: Color(0xFFEFE7DC),
    ),
    LineTheme(
      id: 1,
      name: 'Ocean',
      price: 100,
      line: Color(0xFF1F6FB2),
      head: Color(0xFF123B5C),
      bgTop: Color(0xFFEAF4FB),
      bgBottom: Color(0xFFDCEBF7),
    ),
    LineTheme(
      id: 2,
      name: 'Neon',
      price: 250,
      line: Color(0xFF00E5A0),
      head: Color(0xFF00B4D8),
      bgTop: Color(0xFF161826),
      bgBottom: Color(0xFF1D2032),
      glow: true,
    ),
    LineTheme(
      id: 3,
      name: 'Sunset',
      price: 400,
      line: Color(0xFFFF6B4A),
      head: Color(0xFFB23A48),
      bgTop: Color(0xFFFFF1E6),
      bgBottom: Color(0xFFFFE3D6),
    ),
    LineTheme(
      id: 4,
      name: 'Candy',
      price: 600,
      line: Color(0xFFB14AE2),
      head: Color(0xFFFF4A8D),
      bgTop: Color(0xFFFDF0F7),
      bgBottom: Color(0xFFF9E3F1),
    ),
  ];

  static LineTheme byId(int id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
