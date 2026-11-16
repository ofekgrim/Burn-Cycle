import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../art/palette.dart';
import '../fx/juice.dart';
import '../fx/particles.dart';
import '../game/game_state.dart';

/// Which part of the day the camp is drawn in.
enum CampMood { morning, noon, sunrise, burn }

/// The camp as a 2:1 isometric scene. One scene serves four screens: the
/// build phase, the noon event, the sunrise draft and the burn.
///
/// The scene reads [GameState] and never writes it. Taps are resolved by
/// the Flutter layer through [cellAt].
class CampGame extends FlameGame {
  CampGame({required this.state, required this.mood});

  final GameState state;
  final CampMood mood;

  static const int n = GameState.gridSize;
  static const double maxTile = 130;
  static const double minTile = 22;

  final Shake shake = Shake(maxOffsetX: 9, maxOffsetY: 6, maxRoll: 0);
  final ParticlePool particles = ParticlePool(capacity: 640, priority: 5);
  final ParticlePool wind =
      ParticlePool(capacity: 160, streaks: true, priority: 6);
  final FloatingTexts texts = FloatingTexts(priority: 7);
  final Random _random = Random();

  /// Space covered by Flutter panels, so the grid is laid out between them.
  double topInset = 0;
  double bottomInset = 0;

  double tileW = 64;
  Offset origin = Offset.zero;
  double time = 0;
  int? selectedCell;

  final Map<int, Pop> _pops = {};
  final Map<int, bool> _known = {};
  final List<CrewMember> crew = [];
  double _fireBudget = 0;
  bool _eventStarted = false;
  bool _finaleFired = false;

  double get tileH => tileW / 2;
  FeelSettings get feel => state.feel;

  /// Buildings to draw: the live ones, plus (at noon) the ones the storm is
  /// carrying away.
  Map<int, BuildingType> get blownAway => mood == CampMood.noon
      ? (state.noonEvent?.destroyed ?? const {})
      : const {};

  @override
  Color backgroundColor() => switch (mood) {
        CampMood.morning => Palette.playaMorning,
        CampMood.noon => Palette.playaNoon,
        CampMood.sunrise => Palette.playaSunrise,
        CampMood.burn => Palette.nightGround,
      };

  @override
  Future<void> onLoad() async {
    add(CampScene());
    add(particles);
    add(wind);
    add(texts);
    state.buildings.forEach((cell, b) => _known[cell] = b.anchored);
    final count = min(state.crew, 26);
    for (var i = 0; i < count; i++) {
      crew.add(CrewMember(
        x: _random.nextDouble() * n,
        y: _random.nextDouble() * n,
        color: Palette.festival[i % Palette.festival.length],
        phase: _random.nextDouble() * 6,
      ));
    }
    if (mood == CampMood.sunrise) {
      // Last night's arrivals walk in from the gate.
      final arrivals = min(state.lastNight?.delivered ?? 0, crew.length);
      for (var i = 0; i < arrivals; i++) {
        crew[crew.length - 1 - i]
          ..x = n + 1.5 + i * 0.4
          ..y = n + 1.5 + i * 0.3;
      }
    }
    for (final c in crew) {
      _retarget(c);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout();
  }

  void setInsets(double top, double bottom) {
    if (top == topInset && bottom == bottomInset) return;
    topInset = top;
    bottomInset = bottom;
    if (hasLayout) _layout();
  }

  void _layout() {
    final w = size.x;
    final h = size.y;
    if (w <= 0 || h <= 0) return;
    const headroom = 0.75; // tiles of space above the grid for tall buildings
    final availableH = h - topInset - bottomInset;
    tileW = min((w - 24) / n, availableH / (n / 2 + headroom))
        .clamp(minTile, maxTile);
    final gridH = n * tileH;
    final top = topInset +
        headroom * tileW +
        max(0.0, (availableH - headroom * tileW - gridH) / 2);
    origin = Offset(w / 2, top);
  }

  // ------------------------------------------------------------- geometry

  /// Grid coordinates (fractions allowed) to screen pixels.
  Offset gridToScreen(double gx, double gy) => Offset(
        origin.dx + (gx - gy) * tileW / 2,
        origin.dy + (gx + gy) * tileH / 2,
      );

  Offset cellCenter(int cell) => gridToScreen(cell % n + 0.5, cell ~/ n + 0.5);

  /// The gate: just below the bottom corner of the grid.
  Offset get gate => gridToScreen(n + 0.9, n + 0.9);

  /// Which cell a tap landed on. The tile under the finger wins, so an
  /// empty tile behind a tall building stays tappable. Only a tap that
  /// misses the grid falls back to the bodies of buildings poking above it.
  int? cellAt(Offset p) {
    final dx = (p.dx - origin.dx) / (tileW / 2);
    final dy = (p.dy - origin.dy) / (tileH / 2);
    final gx = ((dx + dy) / 2).floor();
    final gy = ((dy - dx) / 2).floor();
    if (gx >= 0 && gy >= 0 && gx < n && gy < n) return gy * n + gx;
    for (final cell in state.buildings.keys) {
      final c = cellCenter(cell);
      final body = Rect.fromLTRB(
        c.dx - tileW * 0.3,
        c.dy - tileW * 0.55,
        c.dx + tileW * 0.3,
        c.dy,
      );
      if (body.contains(p)) return cell;
    }
    return null;
  }

  int _depth(int cell) => cell % n + cell ~/ n;

  Pop popOf(int cell) => _pops.putIfAbsent(cell, Pop.new);

  // ----------------------------------------------------------------- loop

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.translate(shake.offsetX, shake.offsetY);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void update(double dt) {
    final real = min(dt, 0.05);
    time += real;
    shake.update(real, strength: feel.shakeStrength);
    for (final pop in _pops.values) {
      pop.update(real);
    }
    _detectBuilds();
    _moveCrew(real);
    switch (mood) {
      case CampMood.noon:
        _noon(real);
      case CampMood.burn:
        _burn(real);
      case CampMood.morning:
      case CampMood.sunrise:
        break;
    }
    super.update(real);
  }

  /// Fires feedback when the rules add or anchor a building.
  void _detectBuilds() {
    state.buildings.forEach((cell, building) {
      final known = _known[cell];
      final c = cellCenter(cell);
      if (known == null) {
        popOf(cell).trigger(sx: 1.3, sy: 0.6, duration: 0.26);
        shake.add(specOf(Tier.small).trauma);
        particles.burst(
          c.dx,
          c.dy,
          count: 12,
          color: const Color(0xAAF3E3C3),
          speed: tileW * 1.6,
          life: 0.55,
          size: tileW * 0.07,
          direction: -pi / 2,
          spread: pi,
          gravity: 160,
        );
      } else if (!known && building.anchored) {
        popOf(cell).trigger(sx: 0.88, sy: 1.14, duration: 0.2);
        particles.burst(
          c.dx,
          c.dy,
          count: 8,
          color: Palette.ember,
          speed: tileW * 1.2,
          life: 0.4,
        );
        texts.spawn('מעוגן', c.dx, c.dy - tileW * 0.5, color: Palette.ember);
      }
      _known[cell] = building.anchored;
    });
  }

  void _retarget(CrewMember c) {
    if (mood == CampMood.burn) {
      // Stand in an arc around the fire at the gate.
      final i = crew.indexOf(c);
      final a = pi * 0.15 + (i / max(1, crew.length - 1)) * pi * 0.7;
      final ring = 1.3 + (i % 3) * 0.45;
      c
        ..tx = n + 0.9 - cos(a) * ring * 1.4
        ..ty = n + 0.9 - sin(a) * ring;
      return;
    }
    final free = [
      for (var cell = 0; cell < n * n; cell++)
        if (!state.buildings.containsKey(cell)) cell,
    ];
    if (free.isEmpty) {
      c
        ..tx = n + 0.4
        ..ty = _random.nextDouble() * n;
      return;
    }
    final cell = free[_random.nextInt(free.length)];
    c
      ..tx = cell % n + 0.25 + _random.nextDouble() * 0.5
      ..ty = cell ~/ n + 0.25 + _random.nextDouble() * 0.5;
  }

  void _moveCrew(double dt) {
    for (final c in crew) {
      final dx = c.tx - c.x;
      final dy = c.ty - c.y;
      final d = sqrt(dx * dx + dy * dy);
      c.walking = d > 0.05;
      if (c.walking) {
        final step = min(d, (mood == CampMood.burn ? 1.6 : 0.7) * dt);
        c.x += dx / d * step;
        c.y += dy / d * step;
      } else if (mood != CampMood.burn) {
        c.rest -= dt;
        if (c.rest <= 0) {
          c.rest = 1.5 + _random.nextDouble() * 3;
          _retarget(c);
        }
      }
    }
  }

  // ----------------------------------------------------------------- noon

  void _noon(double dt) {
    final event = state.noonEvent;
    if (event == null) return;
    final stormy =
        event.kind == NoonKind.storm || event.kind == NoonKind.bigStorm;
    if (!_eventStarted && time > 0.15) {
      _eventStarted = true;
      if (stormy) {
        shake.add(event.kind == NoonKind.bigStorm ? 0.9 : 0.5);
      } else if (event.kind == NoonKind.gift) {
        shake.add(0.15);
        particles.burst(
          gate.dx,
          gate.dy - tileW * 0.2,
          count: 22,
          color: Palette.reward,
          speed: tileW * 2.4,
          life: 0.9,
          direction: -pi / 2,
          spread: pi * 1.3,
          gravity: 220,
        );
      }
    }
    if (stormy && time < 2.6) {
      if (event.kind == NoonKind.bigStorm && time < 1.4) shake.add(dt * 0.9);
      _fireBudget += dt * (event.kind == NoonKind.bigStorm ? 110 : 60);
      while (_fireBudget >= 1) {
        _fireBudget -= 1;
        wind.emit(
          -20,
          _random.nextDouble() * size.y,
          900 + _random.nextDouble() * 500,
          200 + _random.nextDouble() * 160,
          color: const Color(0xB0F3E3C3),
          life: 1.4,
          size: 1.5 + _random.nextDouble() * 2,
          drag: 0,
        );
      }
    }
  }

  /// 0..1 strength of the dust haze during a storm.
  double get stormHaze {
    final event = state.noonEvent;
    if (mood != CampMood.noon || event == null) return 0;
    final big = event.kind == NoonKind.bigStorm;
    if (!big && event.kind != NoonKind.storm) return 0;
    final peak = big ? 0.75 : 0.5;
    if (time < 0.4) return peak * time / 0.4;
    return max(0.12, peak * (1 - (time - 0.4) / 2.6));
  }

  // ----------------------------------------------------------------- burn

  /// When a building catches fire, in seconds from the start of the burn.
  double igniteAt(int cell) {
    final order = state.buildings.keys.toList()
      ..sort((a, b) => _depth(a).compareTo(_depth(b)));
    final stagger = min(0.3, 3.6 / max(1, order.length));
    return 0.6 + order.indexOf(cell) * stagger;
  }

  static const double burnSeconds = 2.4;

  /// 0 before the fire, 0..1 while burning, 1 once it is ash.
  double burnProgress(int cell) =>
      ((time - igniteAt(cell)) / burnSeconds).clamp(0.0, 1.0);

  double get _finaleAt {
    var last = 0.6;
    for (final cell in state.buildings.keys) {
      last = max(last, igniteAt(cell));
    }
    return last + burnSeconds;
  }

  void _burn(double dt) {
    final count = max(1, state.buildings.length);
    final rate = min(42.0, 420 / count);
    _fireBudget += dt * rate;
    final emit = _fireBudget.floor();
    _fireBudget -= emit;
    for (final cell in state.buildings.keys) {
      final k = burnProgress(cell);
      if (k <= 0 || k >= 1) continue;
      final c = cellCenter(cell);
      for (var i = 0; i < emit; i++) {
        _flame(c.dx, c.dy - tileW * 0.15 * (1 - k), tileW * 0.3);
      }
    }
    // The fire at the gate burns all night.
    for (var i = 0; i < max(1, emit); i++) {
      _flame(gate.dx, gate.dy, tileW * 0.22);
    }
    if (!_finaleFired && time >= _finaleAt) {
      _finaleFired = true;
      final spec = specOf(Tier.large);
      shake.add(spec.trauma);
      particles.burst(
        origin.dx,
        origin.dy + n * tileH / 2,
        count: spec.particles * 3,
        color: Palette.ember,
        speed: tileW * 4,
        life: 2.2,
        size: 3,
        direction: -pi / 2,
        spread: pi * 1.4,
        drag: 0.8,
        gravity: -30,
      );
    }
  }

  void _flame(double x, double y, double width) {
    final r = _random.nextDouble();
    particles.emit(
      x + (_random.nextDouble() - 0.5) * width * 2,
      y,
      (_random.nextDouble() - 0.5) * 30,
      -50 - _random.nextDouble() * 90,
      color:
          r < 0.25 ? Palette.reward : (r < 0.8 ? Palette.fire : Palette.danger),
      life: 0.5 + _random.nextDouble() * 0.5,
      size: tileW * (0.04 + 0.05 * _random.nextDouble()),
      drag: 0.8,
      gravity: -50,
    );
  }
}

class CrewMember {
  CrewMember({
    required this.x,
    required this.y,
    required this.color,
    required this.phase,
  })  : tx = x,
        ty = y;

  double x;
  double y;
  double tx;
  double ty;
  double rest = 0;
  bool walking = false;
  final Color color;
  final double phase;
}

/// Draws the whole camp: ground, tiles, then buildings and people sorted
/// back to front.
class CampScene extends Component with HasGameReference<CampGame> {
  CampScene() : super(priority: 0);

  final Paint _p = Paint();
  final List<Offset> _specks = [
    for (var i = 0; i < 260; i++)
      Offset(Random(i).nextDouble(), Random(i + 999).nextDouble()),
  ];

  bool get _night => game.mood == CampMood.burn;
  double get _t => game.tileW;

  @override
  void render(Canvas canvas) {
    _ground(canvas);
    _tiles(canvas);

    final items = <_Drawable>[];
    game.state.buildings.forEach((cell, b) {
      items.add(_Drawable(
        (cell % CampGame.n + cell ~/ CampGame.n + 1).toDouble(),
        (c) => _building(c, cell, b.type, b.anchored),
      ));
    });
    game.blownAway.forEach((cell, type) {
      items.add(_Drawable(100, (c) => _blownAway(c, cell, type)));
    });
    for (final person in game.crew) {
      items.add(_Drawable(person.x + person.y, (c) => _person(c, person)));
    }
    items.sort((a, b) => a.depth.compareTo(b.depth));
    for (final item in items) {
      item.draw(canvas);
    }

    _eventProps(canvas);
    _overlay(canvas);
  }

  // --------------------------------------------------------------- ground

  void _ground(Canvas canvas) {
    final size = game.size;
    final center = game.gridToScreen(CampGame.n / 2, CampGame.n / 2);
    final reach = max(size.x, size.y) * 0.75;
    final glow = _night ? const Color(0x40FF7A1A) : const Color(0x55FFF3D6);
    canvas.drawCircle(
      center,
      reach,
      _p
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.radial(center, reach, [
          glow,
          glow.withAlpha(0),
        ]),
    );
    _p.shader = null;
    _p.color = _night ? const Color(0x18E8C9A0) : const Color(0x22503A28);
    for (final s in _specks) {
      canvas.drawCircle(Offset(s.dx * size.x, s.dy * size.y), 1.3, _p);
    }
  }

  Path _diamond(Offset c, double scale) {
    final a = _t / 2 * scale;
    final b = _t / 4 * scale;
    return Path()
      ..moveTo(c.dx, c.dy - b)
      ..lineTo(c.dx + a, c.dy)
      ..lineTo(c.dx, c.dy + b)
      ..lineTo(c.dx - a, c.dy)
      ..close();
  }

  void _tiles(Canvas canvas) {
    final dim = _night ? 0.5 : 1.0;
    for (var cell = 0; cell < CampGame.n * CampGame.n; cell++) {
      final c = game.cellCenter(cell);
      final even = (cell % CampGame.n + cell ~/ CampGame.n).isEven;
      final path = _diamond(c, 0.96);
      canvas.drawPath(
        path,
        _p
          ..style = PaintingStyle.fill
          ..color = Color.fromARGB(
            ((even ? 30 : 16) * dim).round(),
            70,
            45,
            25,
          ),
      );
      canvas.drawPath(
        path,
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.fromARGB((60 * dim).round(), 70, 45, 25),
      );
    }
    final selected = game.selectedCell;
    if (selected != null) {
      canvas.drawPath(
        _diamond(game.cellCenter(selected), 0.96),
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Palette.fire,
      );
    }
    _p.style = PaintingStyle.fill;
  }

  // ------------------------------------------------------------ buildings

  /// An iso box standing on the ground at [c]. [w] is its footprint as a
  /// fraction of the tile, [h] its height in pixels, [lift] how far it
  /// floats. Top, left and right faces get three value bands, lit from the
  /// top left.
  void _box(
    Canvas canvas,
    Offset c,
    double w,
    double h,
    Color color, {
    double lift = 0,
  }) {
    final a = _t / 2 * w;
    final b = _t / 4 * w;
    final gy = c.dy - lift;
    final left = Path()
      ..moveTo(c.dx - a, gy)
      ..lineTo(c.dx, gy + b)
      ..lineTo(c.dx, gy + b - h)
      ..lineTo(c.dx - a, gy - h)
      ..close();
    final right = Path()
      ..moveTo(c.dx + a, gy)
      ..lineTo(c.dx, gy + b)
      ..lineTo(c.dx, gy + b - h)
      ..lineTo(c.dx + a, gy - h)
      ..close();
    final top = Path()
      ..moveTo(c.dx, gy - b - h)
      ..lineTo(c.dx + a, gy - h)
      ..lineTo(c.dx, gy + b - h)
      ..lineTo(c.dx - a, gy - h)
      ..close();
    _p.style = PaintingStyle.fill;
    canvas.drawPath(left, _p..color = Palette.shade(color, 0.78));
    canvas.drawPath(right, _p..color = Palette.shade(color, 0.56));
    canvas.drawPath(top, _p..color = color);
  }

  void _building(Canvas canvas, int cell, BuildingType type, bool anchored) {
    final c = game.cellCenter(cell);
    final burn = _night ? game.burnProgress(cell) : 0.0;

    if (_night && burn > 0 && burn < 1) {
      final flicker = 0.7 + 0.3 * sin(game.time * 17 + cell);
      canvas.drawCircle(
        c,
        _t * 1.1,
        _p
          ..shader = ui.Gradient.radial(c, _t * 1.1, [
            Palette.fire.withAlpha((110 * flicker).round()),
            Palette.fire.withAlpha(0),
          ]),
      );
      _p.shader = null;
    }
    if (burn >= 1) {
      // Ash: a dark smudge, then nothing. Leave no trace.
      canvas.drawOval(
        Rect.fromCenter(center: c, width: _t * 0.5, height: _t * 0.25),
        _p..color = const Color(0x55000000),
      );
      return;
    }

    if (!_night) {
      canvas.drawOval(
        Rect.fromCenter(
          center: c.translate(_t * 0.1, _t * 0.05),
          width: _t * 0.82,
          height: _t * 0.4,
        ),
        _p..color = const Color(0x38000000),
      );
    }
    if (anchored) _anchors(canvas, c);

    final pop = game.popOf(cell);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Burning buildings sag toward the ground as they go.
    canvas.scale(pop.scaleX, pop.scaleY * (1 - 0.85 * easeInCubic(burn)));
    canvas.translate(-c.dx, -c.dy);
    _shape(canvas, c, type, cell, char: burn);
    canvas.restore();
  }

  Color _tint(Color color, double char) =>
      char <= 0 ? color : Color.lerp(color, Palette.char, min(1, char * 1.4))!;

  void _shape(
    Canvas canvas,
    Offset c,
    BuildingType type,
    int cell, {
    double char = 0,
  }) {
    final t = _t;
    final time = game.time;
    switch (type) {
      case BuildingType.shade:
        _p
          ..color = _tint(Palette.woodDark, char)
          ..strokeWidth = max(1.5, t * 0.03);
        for (final corner in [
          Offset(0, -t * 0.17),
          Offset(t * 0.34, 0),
          Offset(0, t * 0.17),
          Offset(-t * 0.34, 0),
        ]) {
          canvas.drawLine(
            c + corner,
            c + corner.translate(0, -t * 0.46),
            _p,
          );
        }
        _box(canvas, c, 0.9, t * 0.05, _tint(const Color(0xFFF08A3C), char),
            lift: t * 0.46);
        _box(canvas, c, 0.5, t * 0.012, _tint(Palette.canvasCream, char),
            lift: t * 0.51);
      case BuildingType.kitchen:
        _box(canvas, c, 0.72, t * 0.2, _tint(Palette.wood, char));
        _p
          ..color = _tint(Palette.woodDark, char)
          ..strokeWidth = max(1.5, t * 0.03);
        canvas.drawLine(
            c.translate(-t * 0.34, 0), c.translate(-t * 0.34, -t * 0.5), _p);
        canvas.drawLine(
            c.translate(t * 0.34, 0), c.translate(t * 0.34, -t * 0.5), _p);
        _box(canvas, c, 0.82, t * 0.05, _tint(Palette.teal, char),
            lift: t * 0.48);
        // Pot, and steam while the kitchen is still standing.
        canvas.drawOval(
          Rect.fromCenter(
            center: c.translate(0, -t * 0.22),
            width: t * 0.2,
            height: t * 0.1,
          ),
          _p..color = _tint(const Color(0xFF3A3A44), char),
        );
        if (char <= 0) {
          for (var i = 0; i < 3; i++) {
            final k = (time * 0.6 + i / 3) % 1.0;
            canvas.drawCircle(
              c.translate(sin(k * 6 + i) * t * 0.04, -t * (0.24 + 0.2 * k)),
              t * (0.025 + 0.03 * k),
              _p
                ..color =
                    Color.fromARGB((130 * (1 - k)).round(), 255, 255, 255),
            );
          }
        }
      case BuildingType.generator:
        final jitter = char <= 0 ? sin(time * 40) * 0.6 : 0.0;
        final g = c.translate(jitter, 0);
        _box(canvas, g, 0.58, t * 0.3, _tint(Palette.generatorYellow, char));
        _box(canvas, g, 0.6, t * 0.05, _tint(const Color(0xFF3A2A1A), char),
            lift: t * 0.1);
        _p
          ..color = _tint(const Color(0xFF55555F), char)
          ..strokeWidth = max(2, t * 0.04);
        canvas.drawLine(g.translate(t * 0.1, -t * 0.34),
            g.translate(t * 0.1, -t * 0.48), _p);
        if (char <= 0) {
          final k = (time * 0.9) % 1.0;
          canvas.drawCircle(
            g.translate(t * 0.1 + k * t * 0.05, -t * (0.5 + 0.16 * k)),
            t * (0.03 + 0.04 * k),
            _p..color = Color.fromARGB((110 * (1 - k)).round(), 90, 90, 90),
          );
          final on = (time * 2).floor().isEven;
          canvas.drawCircle(
            g.translate(-t * 0.14, -t * 0.2),
            t * 0.025,
            _p..color = on ? Palette.good : const Color(0xFF2A5A34),
          );
        }
      case BuildingType.soundStage:
        if (char <= 0) {
          // Bass rings rolling out across the ground.
          for (var i = 0; i < 2; i++) {
            final k = (time / 0.6 + i * 0.5) % 1.0;
            canvas.drawOval(
              Rect.fromCenter(
                center: c,
                width: t * (0.6 + 1.1 * k),
                height: t * (0.3 + 0.55 * k),
              ),
              _p
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Palette.led.withAlpha((170 * (1 - k)).round()),
            );
          }
          _p.style = PaintingStyle.fill;
        }
        _box(canvas, c, 0.88, t * 0.09, _tint(Palette.woodDark, char));
        for (final side in const [-1.0, 1.0]) {
          final s = c.translate(side * t * 0.2, -t * 0.02 * side);
          _box(canvas, s, 0.26, t * 0.4, _tint(Palette.speaker, char),
              lift: t * 0.09);
          if (char <= 0) {
            final thump = 1 + 0.25 * pow(1 - (time / 0.6) % 1.0, 3);
            for (final up in const [0.2, 0.36]) {
              canvas.drawCircle(
                s.translate(-t * 0.035, -t * up),
                t * 0.035 * thump,
                _p..color = Palette.led,
              );
            }
          }
        }
        _box(canvas, c.translate(0, t * 0.06), 0.24, t * 0.13,
            _tint(Palette.violet, char),
            lift: t * 0.09);
      case BuildingType.workshop:
        _box(canvas, c, 0.76, t * 0.32, _tint(Palette.steel, char));
        _box(canvas, c, 0.84, t * 0.05, _tint(const Color(0xFF9DB7C7), char),
            lift: t * 0.32);
        final door = Path()
          ..moveTo(c.dx - t * 0.24, c.dy + t * 0.07)
          ..lineTo(c.dx - t * 0.1, c.dy + t * 0.14)
          ..lineTo(c.dx - t * 0.1, c.dy - t * 0.06)
          ..lineTo(c.dx - t * 0.24, c.dy - t * 0.13)
          ..close();
        canvas.drawPath(door, _p..color = _tint(const Color(0xFF2E3D48), char));
        // Gear on the right wall.
        final gear = c.translate(t * 0.18, -t * 0.08);
        canvas.drawCircle(
          gear,
          t * 0.07,
          _p
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(2, t * 0.035)
            ..color = _tint(Palette.generatorYellow, char),
        );
        _p.style = PaintingStyle.fill;
    }
  }

  void _anchors(Canvas canvas, Offset c) {
    _p
      ..color = _night ? const Color(0x66FFB347) : const Color(0xCC6B3A12)
      ..strokeWidth = max(1.2, _t * 0.018);
    final top = c.translate(0, -_t * 0.42);
    for (final corner in [
      Offset(0, -_t * 0.24),
      Offset(_t * 0.48, 0),
      Offset(0, _t * 0.24),
      Offset(-_t * 0.48, 0),
    ]) {
      final stake = c + corner;
      canvas.drawLine(stake, top, _p);
      canvas.drawLine(stake, stake.translate(0, -_t * 0.07), _p);
    }
  }

  void _blownAway(Canvas canvas, int cell, BuildingType type) {
    const flight = 1.5;
    final k = ((game.time - 0.3) / flight).clamp(0.0, 1.0);
    if (k >= 1) return;
    final c = game.cellCenter(cell);
    final e = easeInCubic(k);
    canvas.save();
    canvas.translate(
      c.dx + e * game.size.x * 0.9,
      c.dy + e * game.size.y * 0.25 - sin(k * pi) * _t,
    );
    canvas.rotate(e * 5);
    canvas.translate(-c.dx, -c.dy);
    _shape(canvas, c, type, cell);
    canvas.restore();
  }

  // --------------------------------------------------------------- people

  void _person(Canvas canvas, CrewMember person, {Color? hat}) {
    final at = game.gridToScreen(person.x, person.y);
    final t = _t;
    final bob = person.walking
        ? -t * 0.03 * sin(game.time * 10 + person.phase).abs()
        : (_night ? -t * 0.02 * sin(game.time * 5 + person.phase).abs() : 0.0);
    canvas.drawOval(
      Rect.fromCenter(center: at, width: t * 0.16, height: t * 0.07),
      _p
        ..style = PaintingStyle.fill
        ..color = const Color(0x40000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          at.dx - t * 0.05,
          at.dy - t * 0.2 + bob,
          t * 0.1,
          t * 0.18,
        ),
        Radius.circular(t * 0.04),
      ),
      _p..color = person.color,
    );
    final head = Offset(at.dx, at.dy - t * 0.25 + bob);
    canvas.drawCircle(head, t * 0.055, _p..color = const Color(0xFFE9B98F));
    if (hat != null) {
      canvas.drawOval(
        Rect.fromCenter(
          center: head.translate(0, -t * 0.04),
          width: t * 0.2,
          height: t * 0.06,
        ),
        _p..color = hat,
      );
    }
  }

  // --------------------------------------------------------------- events

  void _eventProps(Canvas canvas) {
    final t = _t;
    if (_night) {
      // Logs under the fire at the gate.
      _box(canvas, game.gate, 0.4, t * 0.06, Palette.woodDark);
      return;
    }
    final event = game.state.noonEvent;
    if (game.mood != CampMood.noon || event == null) return;
    if (event.kind == NoonKind.gift) {
      // The gift drops in and lands with a bounce.
      final k = (game.time / 0.45).clamp(0.0, 1.0);
      final drop = (1 - easeOutBack(k)) * t * 3;
      final at = game.gate.translate(0, -drop);
      _box(canvas, at, 0.34, t * 0.22, const Color(0xFFE0457B));
      _box(canvas, at, 0.12, t * 0.23, Palette.reward);
    } else if (event.kind == NoonKind.rangers) {
      final k = easeOutCubic((game.time / 1.2).clamp(0.0, 1.0));
      final ranger = CrewMember(
        x: CampGame.n + 3 - 2.1 * k,
        y: CampGame.n + 0.9,
        color: const Color(0xFFB8A070),
        phase: 0,
      )..walking = k < 1;
      _person(canvas, ranger, hat: const Color(0xFF7A6A44));
    }
  }

  void _overlay(Canvas canvas) {
    final bounds = Rect.fromLTWH(-40, -40, game.size.x + 80, game.size.y + 80);
    final haze = game.stormHaze;
    if (haze > 0) {
      canvas.drawRect(
        bounds,
        _p..color = Color.fromARGB((255 * haze).round(), 226, 200, 160),
      );
    }
    final event = game.state.noonEvent;
    if (game.mood == CampMood.noon && event?.kind == NoonKind.heat) {
      // A slow swell, far under any flashing threshold. With reduced
      // flashing it holds steady.
      final swell =
          game.feel.reduceFlashing ? 0.5 : 0.5 + 0.5 * sin(game.time * 1.6);
      canvas.drawRect(
        bounds,
        _p
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, game.size.y),
            [
              Color.fromARGB((70 + 50 * swell).round(), 255, 244, 200),
              const Color(0x00FFF4C8),
            ],
          ),
      );
      _p.shader = null;
    }
    if (game.mood == CampMood.sunrise) {
      canvas.drawRect(
        bounds,
        _p
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, game.size.y),
            const [Color(0x66FF8FA0), Color(0x00FFB347)],
          ),
      );
      _p.shader = null;
    }
  }
}

class _Drawable {
  _Drawable(this.depth, this.draw);

  final double depth;
  final void Function(Canvas canvas) draw;
}
