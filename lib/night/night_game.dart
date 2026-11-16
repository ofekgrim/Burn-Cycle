import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../art/palette.dart';
import '../fx/juice.dart';
import '../fx/particles.dart';
import '../game/game_state.dart';
import '../game/rng.dart';

/// The night phase: drive the art car across the dark playa, pick up
/// wanderers and bring them back to camp before the battery dies.
///
/// Input is fed in from the Flutter layer (see NightScreen): it writes to
/// [steer] and calls [tapBeat]. The game simulates, renders and fires
/// feedback. Feedback never changes the simulation: shake moves the camera,
/// hit-stop scales time.
class NightGame extends FlameGame {
  NightGame({
    required this.config,
    required this.onFinished,
    FeelSettings? feel,
  })  : feel = feel ?? FeelSettings(),
        _random = SeededRng(config.seed);

  final NightConfig config;
  final void Function(NightResult result) onFinished;
  final FeelSettings feel;

  // ---- Tuning. Every number worth arguing about lives here. ----
  static const double fieldRadius = 1100;
  static const double campRadius = 90;
  static const double beatPeriod = 0.6;
  static const double baseSpeed = 230;
  static const double boostMultiplier = 1.6;
  static const double boostDuration = 0.7;
  static const double weightPerPassenger = 0.08;
  static const double lightPerPassenger = 18;
  static const double pickupDistance = 36;

  /// How fast a wanderer walks toward a car whose light has found them.
  static const double attractSpeed = 55;

  /// World units along the square root of the screen area. Phones and
  /// desktops therefore see the same amount of playa.
  static const double viewSpan = 640;

  /// Pause between the night ending and the sunrise screen.
  static const double outroSeconds = 1.0;

  static final Vector2 manPosition = Vector2(0, -620);

  /// Desired direction, each axis in -1..1. Written by the input layer.
  final Vector2 steer = Vector2.zero();

  /// Bumped a few times a second so the Flutter HUD can rebuild.
  final ValueNotifier<int> hud = ValueNotifier<int>(0);

  final ArtCar car = ArtCar();
  final List<Wanderer> wanderers = [];

  /// Shirt colour of everyone on board, in boarding order.
  final List<Color> riders = [];

  final Shake shake = Shake();
  final HitStop hitStop = HitStop();
  final FollowCam followCam = FollowCam(
    rate: 6,
    deadzoneX: 22,
    deadzoneY: 16,
    lookAhead: 90,
    lookRate: 2.5,
    fullLeadSpeed: baseSpeed,
  );
  final ParticlePool dust = ParticlePool(capacity: 160, priority: 2);
  final ParticlePool sparks = ParticlePool(capacity: 420, priority: 12);
  final FloatingTexts texts = FloatingTexts(priority: 20);

  final SeededRng _random;
  final Random _cosmetic = Random();
  final Vector2 _cameraPosition = Vector2.zero();

  late double battery = config.batterySeconds;
  int delivered = 0;
  int combo = 0;
  int maxCombo = 0;
  double beatClock = 0;
  double boostTimer = 0;
  double feedbackTimer = 0;
  bool lastTapHit = false;
  bool finished = false;

  // Playtest readouts.
  int beatTaps = 0;
  int beatHits = 0;
  double elapsed = 0;
  double? firstPickupSeconds;

  /// Signed seconds between the last tap and the beat. Positive is late.
  double lastTapOffset = 0;

  double _hudTimer = 0;
  double _trailBudget = 0;
  double _fireBudget = 0;
  double _zoomPunch = 0;
  double _fenceCooldown = 0;
  double _outro = 0;
  bool _lowBatteryWarned = false;
  bool _reported = false;
  NightResult? _result;

  int get passengers => riders.length;
  bool get atCamp => car.position.length < campRadius;
  bool get boosting => boostTimer > 0;
  double get batteryFraction =>
      (battery / config.batterySeconds).clamp(0.0, 1.0);
  double get lightRadius => config.lightRadius + lightPerPassenger * passengers;

  /// 0 right on the beat, rising to 1 just before the next one.
  double get beatPhase => (beatClock % beatPeriod) / beatPeriod;

  /// 1 on the beat, falling away quickly. Drives everything that pulses.
  double get beatPulse {
    final p = 1 - beatPhase;
    return p * p * p;
  }

  @override
  Color backgroundColor() => Palette.night;

  @override
  Future<void> onLoad() async {
    world.add(PlayaGround(SeededRng(SeededRng.mix(config.seed, 11))));
    world.add(Landmarks(SeededRng(SeededRng.mix(config.seed, 12))));
    world.add(dust);
    world.add(CarLight());
    world.add(CampBeacon());
    for (var i = 0; i < config.wandererCount; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final distance = 260 + _random.nextDouble() * (fieldRadius - 320);
      final wanderer = Wanderer(
        position: Vector2(cos(angle), sin(angle)) * distance,
        color: Palette.festival[_random.nextInt(Palette.festival.length)],
        phase: _random.nextDouble() * 2 * pi,
      );
      wanderers.add(wanderer);
      world.add(wanderer);
    }
    world.add(car);
    world.add(sparks);
    world.add(texts);
    followCam.reset(0, 0);
    if (config.isManNight) {
      texts.spawn(
        'ליל המן',
        0,
        -70,
        color: Palette.fire,
        fontSize: 30,
        life: 2.2,
      );
    }
  }

  // --------------------------------------------------------------- feedback

  /// The one place feedback is fired from. A tier sets the shake, the
  /// hit-stop and the particle count together.
  void feedback(Tier tier, double x, double y, {Color color = Palette.reward}) {
    final spec = specOf(tier);
    shake.add(spec.trauma);
    hitStop.trigger(spec.hitStop);
    sparks.burst(
      x,
      y,
      count: spec.particles,
      color: color,
      speed: 120.0 + 90 * tier.index,
      life: 0.45 + 0.15 * tier.index,
    );
    if (tier == Tier.large) _zoomPunch = 1;
  }

  /// Called by the input layer when the player taps for the beat.
  void tapBeat() {
    if (finished) return;
    final t = beatClock % beatPeriod;
    final offset = min(t, beatPeriod - t);
    lastTapOffset = t < beatPeriod / 2 ? t : t - beatPeriod;
    lastTapHit = offset <= config.beatWindow;
    feedbackTimer = 0.25;
    beatTaps += 1;
    final x = car.position.x;
    final y = car.position.y;
    if (lastTapHit) {
      beatHits += 1;
      combo += 1;
      maxCombo = max(maxCombo, combo);
      boostTimer = boostDuration;
      final perfect = offset <= config.beatWindow / 3;
      // Stretch along the direction of travel as the boost kicks in.
      car.pop.trigger(sx: 1.3, sy: 0.78);
      feedback(
        perfect ? Tier.medium : Tier.small,
        x,
        y,
        color: perfect ? Palette.reward : Palette.led,
      );
      if (perfect) {
        texts.spawn('מושלם!', x, y - 44, color: Palette.reward, fontSize: 20);
      }
      if (combo % 5 == 0) {
        texts.spawn(
          'קומבו ×$combo',
          x,
          y - 74,
          color: Palette.led,
          fontSize: 26,
          life: 1.1,
        );
        _zoomPunch = 1;
      }
    } else {
      if (combo >= 3) {
        texts.spawn('הקומבו נשבר', x, y - 44, color: Palette.danger);
      }
      combo = 0;
      car.pop.trigger(sx: 0.9, sy: 1.12, duration: 0.14);
    }
  }

  /// Ends the night on purpose. Only valid while parked at camp.
  void endNightAtCamp() {
    if (atCamp) _finish(stranded: false);
  }

  // ------------------------------------------------------------------- loop

  @override
  void update(double dt) {
    // A long frame (tab in the background) must not teleport the car.
    final real = min(dt, 0.05);
    hitStop.update(real);
    shake.update(real, strength: feel.shakeStrength);
    final scaled = real * hitStop.timeScale;

    if (finished) {
      _outro -= real;
      if (_outro <= 0 && !_reported) {
        _reported = true;
        onFinished(_result!);
      }
    } else {
      _simulate(scaled);
    }

    super.update(scaled);
    // The camera moves last, after its target has.
    _updateCamera(real);

    _hudTimer += real;
    if (_hudTimer >= 0.1) {
      _hudTimer = 0;
      hud.value += 1;
    }
  }

  void _simulate(double dt) {
    elapsed += dt;
    beatClock += dt;
    if (boostTimer > 0) boostTimer -= dt;
    if (feedbackTimer > 0) feedbackTimer -= dt;
    if (_fenceCooldown > 0) _fenceCooldown -= dt;
    car.pop.update(dt);

    // Heavier car = slower car.
    final weight = max(0.4, 1 - weightPerPassenger * passengers);
    final speed =
        baseSpeed * config.speedMul * weight * (boosting ? boostMultiplier : 1);

    // Ease velocity toward the steering target for a bit of inertia.
    final k = 1 - exp(-6 * dt);
    car.velocity.x += (steer.x * speed - car.velocity.x) * k;
    car.velocity.y += (steer.y * speed - car.velocity.y) * k;

    var x = car.position.x + car.velocity.x * dt;
    var y = car.position.y + car.velocity.y * dt;
    final distance = sqrt(x * x + y * y);
    if (distance > fieldRadius) {
      x = x / distance * fieldRadius;
      y = y / distance * fieldRadius;
      if (_fenceCooldown <= 0 && car.velocity.length > 90) {
        _fenceCooldown = 0.8;
        feedback(Tier.small, x, y, color: Palette.fire);
        texts.spawn('גדר הפלאיה', x, y - 40, color: Palette.fire);
      }
    }
    car.position.setValues(x, y);
    if (car.velocity.length > 8) {
      car.heading = atan2(car.velocity.y, car.velocity.x);
    }

    battery -= dt * (boosting ? 1.5 : 1);
    _emitTrail(dt);
    if (config.isManNight) _burnTheMan(dt);

    // Pick up wanderers while there is a free seat.
    for (var i = wanderers.length - 1;
        i >= 0 && passengers < config.seats;
        i--) {
      final wanderer = wanderers[i];
      if (wanderer.position.distanceTo(car.position) < pickupDistance) {
        wanderers.removeAt(i);
        wanderer.removeFromParent();
        _pickUp(wanderer);
      }
    }

    // Drop everyone off when passing through camp.
    if (atCamp && passengers > 0) _dropOff();

    if (!_lowBatteryWarned && batteryFraction < 0.25) {
      _lowBatteryWarned = true;
      shake.add(0.2);
      texts.spawn(
        'סוללה נמוכה, חזרו לקאמפ',
        car.position.x,
        car.position.y - 54,
        color: Palette.danger,
        life: 1.6,
      );
    }

    if (battery <= 0) {
      _finish(stranded: !atCamp);
    } else if (wanderers.isEmpty && passengers == 0) {
      _finish(stranded: false);
    }
  }

  void _pickUp(Wanderer wanderer) {
    riders.add(wanderer.color);
    firstPickupSeconds ??= elapsed;
    // Pickups happen dozens of times a night, so they stay in the small
    // tier. The big moments are the drop-off and a perfect beat.
    car.pop.trigger(sx: 1.22, sy: 0.82);
    feedback(
      Tier.small,
      wanderer.position.x,
      wanderer.position.y,
      color: wanderer.color,
    );
    texts.spawn(
      passengers >= config.seats ? 'מלא!' : '+1',
      wanderer.position.x,
      wanderer.position.y - 20,
      color: wanderer.color,
    );
  }

  void _dropOff() {
    final count = passengers;
    delivered += count;
    for (final color in riders) {
      sparks.burst(
        0,
        0,
        count: 6,
        color: color,
        speed: 240,
        life: 0.8,
        direction: -pi / 2,
        spread: pi * 1.2,
        gravity: 260,
      );
    }
    riders.clear();
    feedback(count >= 3 ? Tier.large : Tier.medium, 0, 0, color: Palette.ember);
    texts.spawn(
      '+$count לקאמפ',
      0,
      -56,
      color: Palette.reward,
      fontSize: 28,
      life: 1.3,
      rise: 60,
    );
    car.pop.trigger(sx: 0.8, sy: 1.25);
  }

  void _emitTrail(double dt) {
    if (car.velocity.length < 40) return;
    _trailBudget += dt * (boosting ? 60 : 26);
    final back = car.heading + pi;
    final bx = car.position.x + cos(back) * 20;
    final by = car.position.y + sin(back) * 20;
    while (_trailBudget >= 1) {
      _trailBudget -= 1;
      final jx = (_cosmetic.nextDouble() - 0.5) * 14;
      final jy = (_cosmetic.nextDouble() - 0.5) * 14;
      dust.emit(
        bx + jx,
        by + jy,
        cos(back) * 24 + jx,
        sin(back) * 24 + jy,
        color: const Color(0x55E8C9A0),
        life: 0.8,
        size: 6,
        drag: 3,
      );
      if (boosting) {
        sparks.emit(
          bx,
          by,
          cos(back) * 110 + jx * 6,
          sin(back) * 110 + jy * 6,
          color: _cosmetic.nextBool() ? Palette.fire : Palette.reward,
          life: 0.32,
          size: 3,
        );
      }
    }
  }

  void _burnTheMan(double dt) {
    _fireBudget += dt * 45;
    while (_fireBudget >= 1) {
      _fireBudget -= 1;
      final spread = (_cosmetic.nextDouble() - 0.5) * 60;
      sparks.emit(
        manPosition.x + spread,
        manPosition.y - _cosmetic.nextDouble() * 110,
        spread * 0.4,
        -60 - _cosmetic.nextDouble() * 110,
        color: _cosmetic.nextDouble() < 0.6 ? Palette.fire : Palette.reward,
        life: 0.9,
        size: 5,
        drag: 0.6,
        gravity: -40,
      );
    }
  }

  void _finish({required bool stranded}) {
    if (finished) return;
    finished = true;
    var lost = 0;
    if (stranded) {
      // Half of the people on board give up and walk off into the dark.
      lost = (passengers / 2).ceil();
    }
    delivered += passengers - lost;
    riders.clear();
    steer.setZero();
    car.velocity.setZero();
    final x = car.position.x;
    final y = car.position.y;
    if (stranded) {
      feedback(Tier.large, x, y, color: Palette.danger);
      texts.spawn(
        'הסוללה נגמרה',
        x,
        y - 50,
        color: Palette.danger,
        fontSize: 26,
        life: 1.4,
      );
    } else {
      texts.spawn(
        'הלילה נגמר',
        x,
        y - 50,
        color: Palette.reward,
        fontSize: 26,
        life: 1.4,
      );
    }
    _result = NightResult(
      delivered: delivered,
      lost: lost,
      maxCombo: maxCombo,
      stranded: stranded,
      beatTaps: beatTaps,
      beatHits: beatHits,
      firstPickupSeconds: firstPickupSeconds,
    );
    _outro = outroSeconds;
    hud.value += 1;
  }

  void _updateCamera(double dt) {
    if (size.x <= 0 || size.y <= 0) return;
    if (_zoomPunch > 0) _zoomPunch = max(0, _zoomPunch - dt * 4);
    final base = (sqrt(size.x * size.y) / viewSpan).clamp(0.7, 2.4);
    final zoom = base * (1 + 0.05 * _zoomPunch * feel.shakeStrength);
    followCam
      ..update(
        dt,
        targetX: car.position.x,
        targetY: car.position.y,
        velX: car.velocity.x,
        velY: car.velocity.y,
      )
      ..clampView(
        minX: -fieldRadius - 260,
        maxX: fieldRadius + 260,
        minY: -fieldRadius - 260,
        maxY: fieldRadius + 260,
        halfViewW: size.x / zoom / 2,
        halfViewH: size.y / zoom / 2,
      );
    // Shake rides on top of the smoothed follow and is never fed back in.
    _cameraPosition.setValues(
      followCam.x + shake.offsetX / zoom,
      followCam.y + shake.offsetY / zoom,
    );
    camera.viewfinder
      ..zoom = zoom
      ..position = _cameraPosition
      ..angle = shake.roll;
  }
}

/// The player's vehicle. Movement is driven by [NightGame.update].
class ArtCar extends PositionComponent with HasGameReference<NightGame> {
  ArtCar() : super(size: Vector2.all(44), anchor: Anchor.center, priority: 10);

  final Vector2 velocity = Vector2.zero();
  final Pop pop = Pop();
  double heading = 0;

  final Paint _body = Paint()..color = Palette.fire;
  final Paint _deck = Paint()..color = const Color(0xFF7A3208);
  final Paint _headlight = Paint()..color = const Color(0xFFFFF6D8);
  final Paint _paint = Paint();

  static final RRect _bodyRect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 46, height: 26),
    const Radius.circular(9),
  );
  static final RRect _deckRect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: const Offset(-4, 0), width: 28, height: 17),
    const Radius.circular(5),
  );

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final pulse = game.beatPulse;

    // Fixed target ring, and the beat ring that shrinks onto it.
    canvas.drawCircle(
      center,
      26,
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Palette.violet.withAlpha(70),
    );
    final phase = game.beatPhase;
    final ringRadius = 26 + 46 * (1 - phase);
    final onBeat = phase < 0.12 || phase > 0.88;
    final ringColor = game.feedbackTimer > 0
        ? (game.lastTapHit ? Palette.good : Palette.danger)
        : (onBeat ? Palette.reward : Palette.violet);
    canvas.drawCircle(
      center,
      ringRadius,
      _paint
        ..strokeWidth = onBeat ? 4 : 2
        ..color = ringColor.withAlpha(onBeat ? 230 : 120),
    );
    _paint.style = PaintingStyle.fill;

    // Arrow pointing home when the camp is off screen.
    final toCamp = -position;
    if (toCamp.length > 320) {
      final angle = atan2(toCamp.y, toCamp.x);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final arrow = Path()
        ..moveTo(100, 0)
        ..lineTo(82, -9)
        ..lineTo(82, 9)
        ..close();
      canvas.drawPath(arrow, _paint..color = Palette.ember);
      canvas.restore();
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(heading);
    canvas.scale(pop.scaleX, pop.scaleY);

    // Underglow, brighter on the beat and as the combo grows.
    final glow = (40 + 70 * pulse + 6 * min(game.combo, 10)).round();
    canvas.drawRRect(
      _bodyRect.inflate(7),
      _paint..color = Palette.led.withAlpha(glow.clamp(0, 200)),
    );

    if (game.boosting) {
      final flame = Path()
        ..moveTo(-22, -8)
        ..lineTo(-40 - 10 * pulse, 0)
        ..lineTo(-22, 8)
        ..close();
      canvas.drawPath(flame, _paint..color = Palette.reward);
    }

    canvas.drawRRect(_bodyRect, _body);
    canvas.drawRRect(_deckRect, _deck);
    canvas.drawCircle(const Offset(19, -8), 3.2, _headlight);
    canvas.drawCircle(const Offset(19, 8), 3.2, _headlight);

    // LED strips down both sides. The hue drifts faster as the combo grows.
    for (var i = 0; i < 6; i++) {
      final hue =
          (game.beatClock * (60 + 25 * min(game.combo, 10)) + i * 42) % 360;
      _paint.color =
          HSVColor.fromAHSV(1, hue, 0.75, 0.6 + 0.4 * pulse).toColor();
      final x = -18.0 + i * 7;
      canvas.drawCircle(Offset(x, -13), 1.9, _paint);
      canvas.drawCircle(Offset(x, 13), 1.9, _paint);
    }

    // One head per passenger, in their own colour.
    for (var i = 0; i < game.riders.length; i++) {
      final column = i ~/ 2;
      final row = i % 2;
      canvas.drawCircle(
        Offset(-13.0 + column * 7.5, row == 0 ? -4.5 : 4.5),
        3.2,
        _paint..color = game.riders[i],
      );
    }
    canvas.restore();
  }
}

/// Warm pool of light around the car, plus a headlight cone. The pool grows
/// with every passenger.
class CarLight extends Component with HasGameReference<NightGame> {
  CarLight() : super(priority: 3);

  final Paint _pool = Paint();
  final Paint _cone = Paint();
  double _shaderRadius = -1;
  Path _conePath = Path();

  @override
  void render(Canvas canvas) {
    final radius = game.lightRadius;
    if (radius != _shaderRadius) {
      _shaderRadius = radius;
      _pool.shader = ui.Gradient.radial(Offset.zero, radius, const [
        Color(0x66FFB347),
        Color(0x22FF7A1A),
        Color(0x00000000),
      ], const [
        0.0,
        0.6,
        1.0,
      ]);
      final reach = radius * 1.25;
      _cone.shader = ui.Gradient.radial(Offset.zero, reach, const [
        Color(0x55FFF6D8),
        Color(0x00FFF6D8),
      ]);
      _conePath = Path()
        ..moveTo(14, 0)
        ..lineTo(cos(-0.42) * reach, sin(-0.42) * reach)
        ..arcToPoint(
          Offset(cos(0.42) * reach, sin(0.42) * reach),
          radius: Radius.circular(reach),
        )
        ..close();
    }
    canvas.save();
    canvas.translate(game.car.position.x, game.car.position.y);
    canvas.drawCircle(Offset.zero, radius, _pool);
    canvas.rotate(game.car.heading);
    canvas.drawPath(_conePath, _cone);
    canvas.restore();
  }
}

/// A person out on the playa. Bright inside the car's light, a faint glimmer
/// outside it. Once the light finds them they run for the car.
class Wanderer extends PositionComponent with HasGameReference<NightGame> {
  Wanderer({
    required Vector2 position,
    required this.color,
    required double phase,
  })  : _phase = phase,
        _home = position.clone(),
        _head = Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!,
        super(
          position: position,
          size: Vector2.all(20),
          anchor: Anchor.center,
          priority: 5,
        );

  final Color color;
  final Color _head;
  final Vector2 _home;
  final double _phase;
  final Paint _paint = Paint();
  double _time = 0;
  bool attracted = false;

  @override
  void update(double dt) {
    _time += dt;
    final car = game.car.position;
    final dx = car.x - position.x;
    final dy = car.y - position.y;
    final distance = sqrt(dx * dx + dy * dy);
    attracted = !game.finished &&
        distance < game.lightRadius &&
        game.passengers < game.config.seats;
    if (attracted && distance > 1) {
      position.x += dx / distance * NightGame.attractSpeed * dt;
      position.y += dy / distance * NightGame.attractSpeed * dt;
    } else {
      // Mill about near where they were standing.
      final k = min(1.0, dt * 0.8);
      position.x += (_home.x + 14 * sin(_time * 0.7 + _phase) - position.x) * k;
      position.y += (_home.y + 14 * cos(_time * 0.5 + _phase) - position.y) * k;
    }
  }

  @override
  void render(Canvas canvas) {
    final distance = position.distanceTo(game.car.position);
    final light = game.lightRadius;
    final int alpha;
    if (distance < light) {
      alpha = 255;
    } else if (distance < light * 2.2) {
      alpha = 90;
    } else {
      alpha = 26;
    }
    final hop = attracted
        ? -3 * sin(_time * 11 + _phase).abs()
        : 1.2 * sin(_time * 3 + _phase);
    final cx = size.x / 2;
    final cy = size.y / 2 + hop;
    final pulse = 1 + 0.15 * sin(_time * 3 + _phase);
    canvas.drawCircle(
      Offset(cx, cy),
      12 * pulse,
      _paint..color = color.withAlpha(alpha ~/ 4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 3), width: 8, height: 10),
        const Radius.circular(3.5),
      ),
      _paint..color = color.withAlpha(alpha),
    );
    canvas.drawCircle(
      Offset(cx, cy - 5),
      3.6,
      _paint..color = _head.withAlpha(alpha),
    );
    if (attracted) {
      // Arms up: they have seen the car.
      _paint
        ..color = color.withAlpha(alpha)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx - 4, cy), Offset(cx - 8, cy - 7), _paint);
      canvas.drawLine(Offset(cx + 4, cy), Offset(cx + 8, cy - 7), _paint);
    }
  }
}

/// The camp at the centre of the map: the drop-off zone. Two slow
/// searchlights make it findable from far away.
class CampBeacon extends Component with HasGameReference<NightGame> {
  CampBeacon() : super(priority: 4);

  static const double _beamLength = 430;

  double _time = 0;
  final Paint _paint = Paint();
  final Paint _beam = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, _beamLength, const [
      Color(0x50FFB347),
      Color(0x00FFB347),
    ]);

  @override
  void update(double dt) {
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final pulse = 0.5 + 0.5 * sin(_time * 2);
    for (var i = 0; i < 2; i++) {
      final a = _time * 0.45 + i * pi;
      final beam = Path()
        ..moveTo(0, 0)
        ..lineTo(cos(a - 0.06) * _beamLength, sin(a - 0.06) * _beamLength)
        ..lineTo(cos(a + 0.06) * _beamLength, sin(a + 0.06) * _beamLength)
        ..close();
      canvas.drawPath(beam, _beam);
    }
    canvas.drawCircle(
      Offset.zero,
      NightGame.campRadius,
      _paint
        ..style = PaintingStyle.fill
        ..color = Palette.ember.withAlpha(24 + (30 * pulse).round()),
    );
    canvas.drawCircle(
      Offset.zero,
      NightGame.campRadius + 4 * game.beatPulse,
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Palette.ember.withAlpha(150 + (100 * pulse).round()),
    );
    _paint.style = PaintingStyle.fill;
    _tent(canvas, const Offset(0, -6), 1.0, Palette.canvasCream);
    _tent(canvas, const Offset(-38, 14), 0.7, Palette.teal);
    _tent(canvas, const Offset(38, 16), 0.7, Palette.violet);
  }

  void _tent(Canvas canvas, Offset at, double scale, Color color) {
    final tent = Path()
      ..moveTo(at.dx, at.dy - 30 * scale)
      ..lineTo(at.dx + 28 * scale, at.dy + 20 * scale)
      ..lineTo(at.dx - 28 * scale, at.dy + 20 * scale)
      ..close();
    canvas.drawPath(tent, _paint..color = color);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(at.dx, at.dy + 10 * scale),
        width: 10 * scale,
        height: 20 * scale,
      ),
      _paint..color = const Color(0xFF3A2A1A),
    );
  }
}

/// The ground: dust specks so movement reads in the dark, the faint streets
/// of the city, and the fence around the playable area.
class PlayaGround extends Component {
  PlayaGround(Random random)
      : _points = Float32List(1400),
        super(priority: 0) {
    const extent = NightGame.fieldRadius + 260;
    for (var i = 0; i < _points.length; i++) {
      _points[i] = (random.nextDouble() * 2 - 1) * extent;
    }
  }

  final Float32List _points;

  final Paint _dust = Paint()
    ..color = const Color(0x55E8C9A0)
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  final Paint _street = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 30
    ..color = const Color(0x0BE8C9A0);

  final Paint _fence = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..color = const Color(0x66FF7A1A);

  final Paint _post = Paint()..color = const Color(0xAAFF7A1A);

  @override
  void render(Canvas canvas) {
    // Ring roads and radial streets, like the city plan.
    for (final radius in const [330.0, 580.0, 830.0]) {
      canvas.drawCircle(Offset.zero, radius, _street);
    }
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      canvas.drawLine(
        Offset(cos(a) * 150, sin(a) * 150),
        Offset(cos(a) * 1000, sin(a) * 1000),
        _street,
      );
    }
    canvas.drawRawPoints(ui.PointMode.points, _points, _dust);
    canvas.drawCircle(Offset.zero, NightGame.fieldRadius, _fence);
    for (var i = 0; i < 72; i++) {
      final a = i * pi / 36;
      canvas.drawCircle(
        Offset(cos(a), sin(a)) * NightGame.fieldRadius,
        5,
        _post,
      );
    }
  }
}

/// Neon art out on the playa, and the Man. They glow on their own, so they
/// work as landmarks for finding the way in the dark.
class Landmarks extends Component with HasGameReference<NightGame> {
  Landmarks(Random random) : super(priority: 1) {
    const colors = [
      Palette.led,
      Palette.violet,
      Color(0xFFFF5FA2),
      Palette.good,
      Palette.reward,
      Palette.led,
    ];
    for (var i = 0; i < 6; i++) {
      // One piece per sixth of the circle, so they never bunch up.
      final angle = (i + 0.2 + 0.6 * random.nextDouble()) * pi / 3;
      final distance = 380 + random.nextDouble() * 480;
      final at = Offset(cos(angle), sin(angle)) * distance;
      _pieces.add(_Piece(_shape(i).shift(at), colors[i]));
    }
  }

  final List<_Piece> _pieces = [];
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  static Path _shape(int kind) {
    switch (kind) {
      case 0: // pyramid
        return Path()
          ..moveTo(0, -60)
          ..lineTo(52, 40)
          ..lineTo(-52, 40)
          ..close()
          ..moveTo(0, -60)
          ..lineTo(0, 40);
      case 1: // rings
        return Path()
          ..addOval(Rect.fromCircle(center: Offset.zero, radius: 50))
          ..addOval(Rect.fromCircle(center: Offset.zero, radius: 28));
      case 2: // four-point star
        return Path()
          ..moveTo(0, -64)
          ..lineTo(14, -14)
          ..lineTo(64, 0)
          ..lineTo(14, 14)
          ..lineTo(0, 64)
          ..lineTo(-14, 14)
          ..lineTo(-64, 0)
          ..lineTo(-14, -14)
          ..close();
      case 3: // heart
        return Path()
          ..moveTo(0, 46)
          ..cubicTo(-70, -6, -34, -64, 0, -24)
          ..cubicTo(34, -64, 70, -6, 0, 46)
          ..close();
      case 4: // temple arches
        return Path()
          ..addArc(
              Rect.fromCircle(center: const Offset(0, 30), radius: 60), pi, pi)
          ..addArc(
              Rect.fromCircle(center: const Offset(0, 30), radius: 40), pi, pi)
          ..addArc(
              Rect.fromCircle(center: const Offset(0, 30), radius: 20), pi, pi)
          ..moveTo(-60, 30)
          ..lineTo(60, 30);
      default: // cube
        return Path()
          ..moveTo(0, -52)
          ..lineTo(48, -24)
          ..lineTo(48, 28)
          ..lineTo(0, 56)
          ..lineTo(-48, 28)
          ..lineTo(-48, -24)
          ..close()
          ..moveTo(0, 4)
          ..lineTo(0, 56)
          ..moveTo(0, 4)
          ..lineTo(48, -24)
          ..moveTo(0, 4)
          ..lineTo(-48, -24);
    }
  }

  /// A stroke with two wider, fainter strokes under it reads as neon
  /// without a blur filter.
  void _neon(Canvas canvas, Path path, Color color, double strength) {
    canvas.drawPath(
      path,
      _paint
        ..strokeWidth = 12
        ..color = color.withAlpha((34 * strength).round()),
    );
    canvas.drawPath(
      path,
      _paint
        ..strokeWidth = 6
        ..color = color.withAlpha((80 * strength).round()),
    );
    canvas.drawPath(
      path,
      _paint
        ..strokeWidth = 2.2
        ..color = color.withAlpha((230 * strength).round()),
    );
  }

  @override
  void render(Canvas canvas) {
    final strength = 0.55 + 0.45 * game.beatPulse;
    for (final piece in _pieces) {
      _neon(canvas, piece.path, piece.color, strength);
    }

    // The Man: arms up, on a plinth, north of camp.
    final m = NightGame.manPosition;
    final burning = game.config.isManNight;
    final man = Path()
      ..moveTo(m.x - 22, m.y + 60)
      ..lineTo(m.x, m.y)
      ..lineTo(m.x + 22, m.y + 60)
      ..moveTo(m.x, m.y)
      ..lineTo(m.x, m.y - 50)
      ..moveTo(m.x - 40, m.y - 86)
      ..lineTo(m.x, m.y - 40)
      ..lineTo(m.x + 40, m.y - 86)
      ..addOval(Rect.fromCircle(center: Offset(m.x, m.y - 64), radius: 10))
      ..addRect(Rect.fromLTWH(m.x - 46, m.y + 60, 92, 18));
    if (burning) {
      canvas.drawCircle(
        Offset(m.x, m.y - 20),
        150 + 20 * game.beatPulse,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(m.x, m.y - 20),
            170,
            const [Color(0x66FF7A1A), Color(0x00FF7A1A)],
          ),
      );
    }
    _neon(canvas, man, burning ? Palette.reward : Palette.fire, strength);
  }
}

class _Piece {
  _Piece(this.path, this.color);

  final Path path;
  final Color color;
}
