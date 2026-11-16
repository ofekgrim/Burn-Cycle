import 'dart:ui';

/// Colour roles shared by every scene (see docs/ART_DIRECTION.md).
///
/// Scenes pick a colour by what it means, so the same orange is always
/// "you / fire" and the same cyan is always "neon you can interact with".
abstract final class Palette {
  // Night
  static const Color night = Color(0xFF0B0714);
  static const Color nightGround = Color(0xFF17100F);

  // Accents
  static const Color fire = Color(0xFFFF7A1A); // the player, flames
  static const Color ember = Color(0xFFFFB347); // warm light, camp, home
  static const Color reward = Color(0xFFFFE08A); // beat, perfect, payoff
  static const Color led = Color(0xFF39F0FF); // interactive neon
  static const Color violet = Color(0xFFB98CFF); // idle beat, ambience
  static const Color good = Color(0xFF6BFF8A);
  static const Color danger = Color(0xFFFF5A5A);

  // Playa
  static const Color sand = Color(0xFFE8C9A0);
  static const Color playaMorning = Color(0xFFD9BC92);
  static const Color playaNoon = Color(0xFFE9D6AE);
  static const Color playaSunrise = Color(0xFFD7A088);

  // Materials
  static const Color wood = Color(0xFF9A6A44);
  static const Color woodDark = Color(0xFF5A3A2A);
  static const Color canvasCream = Color(0xFFF3E3C3);
  static const Color teal = Color(0xFF3FB8A9);
  static const Color generatorYellow = Color(0xFFF2C230);
  static const Color steel = Color(0xFF6E8FA6);
  static const Color speaker = Color(0xFF2A2330);
  static const Color char = Color(0xFF2B1D17);

  // UI
  static const Color panel = Color(0xE01C1210);

  /// Shirt colours for crew and wanderers.
  static const List<Color> festival = [
    Color(0xFFFF5FA2),
    Color(0xFF39F0FF),
    Color(0xFFFFE08A),
    Color(0xFF6BFF8A),
    Color(0xFFB98CFF),
    Color(0xFFFF7A1A),
  ];

  /// Darkens or lightens [color] by [factor] (1 = unchanged).
  static Color shade(Color color, double factor) {
    int channel(double v) => (v * 255 * factor).round().clamp(0, 255);
    return Color.fromARGB(
      (color.a * 255).round(),
      channel(color.r),
      channel(color.g),
      channel(color.b),
    );
  }
}
