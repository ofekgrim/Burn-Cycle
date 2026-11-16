import 'dart:math';

/// Game-feel primitives. Pure Dart: nothing here knows about Flame or
/// Flutter, so every rule can be stepped headless in a unit test.
///
/// Two clocks matter. "Real" time always advances; "scaled" time is real
/// time multiplied by [HitStop.timeScale]. Shake decays on real time so it
/// never freezes off-centre during a hit-stop. Poses ([Pop]) run on scaled
/// time, so they hold still while the world is frozen.

/// How big a moment is. Every game event maps to one tier and fires that
/// tier's bundle, which keeps feedback proportional across the whole game.
enum Tier { small, medium, large }

class TierSpec {
  const TierSpec({
    required this.trauma,
    required this.hitStop,
    required this.particles,
  });

  final double trauma;

  /// Seconds of hit-stop, 0 for none.
  final double hitStop;
  final int particles;
}

TierSpec specOf(Tier tier) => switch (tier) {
      Tier.small => const TierSpec(trauma: 0.15, hitStop: 0, particles: 4),
      Tier.medium => const TierSpec(trauma: 0.4, hitStop: 0.05, particles: 10),
      Tier.large => const TierSpec(trauma: 0.8, hitStop: 0.12, particles: 28),
    };

/// Player-facing comfort options.
class FeelSettings {
  /// Scales every shake, roll and zoom punch. 0 turns camera motion off.
  double shakeStrength = 0.7;

  /// Swaps pulsing full-screen effects for a steady tint.
  bool reduceFlashing = false;
}

// ------------------------------------------------------------------ easing

/// Overshoots past 1 and settles back: the curve for pops.
double easeOutBack(double k) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final m = k - 1;
  return 1 + c3 * m * m * m + c1 * m * m;
}

/// Decelerates into rest.
double easeOutCubic(double k) {
  final m = 1 - k;
  return 1 - m * m * m;
}

/// Slow start: anticipation, things falling away.
double easeInCubic(double k) => k * k * k;

// ------------------------------------------------------------------- shake

/// Screen shake driven by a decaying trauma value.
///
/// Events add trauma; it drains linearly. The visible shake is trauma
/// squared, so small events barely move the screen and big ones punch.
/// The offsets are for the camera only, never for anything that collides.
class Shake {
  Shake({
    this.decay = 1.2,
    this.maxOffsetX = 12,
    this.maxOffsetY = 8,
    this.maxRoll = 0.04,
  });

  /// Trauma lost per real second.
  final double decay;
  final double maxOffsetX;
  final double maxOffsetY;

  /// Radians.
  final double maxRoll;

  double trauma = 0;
  double offsetX = 0;
  double offsetY = 0;
  double roll = 0;
  double _t = 0;

  /// Hits stack up to 1; they never reset a shake already in progress.
  void add(double amount) {
    trauma = (trauma + amount).clamp(0.0, 1.0);
  }

  /// Advance by real (unscaled) seconds.
  void update(double realDt, {double strength = 1}) {
    if (trauma <= 0) return;
    trauma = max(0, trauma - decay * realDt);
    if (trauma == 0) {
      offsetX = 0;
      offsetY = 0;
      roll = 0;
      return;
    }
    final amount = trauma * trauma * strength;
    _t += realDt * 30;
    // Sines at unrelated rates read as a shake. A fresh random offset every
    // frame reads as static.
    offsetX = maxOffsetX * amount * sin(_t * 1.7);
    offsetY = maxOffsetY * amount * sin(_t * 2.3);
    roll = maxRoll * amount * sin(_t * 1.1);
  }
}

// ---------------------------------------------------------------- hit-stop

/// Brief slow-down on impact.
///
/// One countdown owns the restore, so overlapping hits cannot hand time back
/// in the middle of a later freeze. A continuous freeze is capped at
/// [maxStop] and followed by a short cooldown, so a burst of hits can never
/// lock the game or swallow input.
class HitStop {
  HitStop({this.maxStop = 0.15, this.cooldown = 0.1});

  final double maxStop;
  final double cooldown;

  double _remaining = 0;
  double _frozenFor = 0;
  double _cooldownLeft = 0;
  double _slow = 1;

  bool get active => _remaining > 0;

  /// Multiply the world's delta time by this.
  double get timeScale => active ? _slow : 1;

  void trigger(double duration, {double slow = 0.05}) {
    if (duration <= 0 || _cooldownLeft > 0) return;
    final budget = maxStop - _frozenFor;
    if (budget <= 0) return;
    _remaining = min(max(_remaining, duration), budget);
    _slow = slow;
  }

  /// Advance by real (unscaled) seconds.
  void update(double realDt) {
    if (_cooldownLeft > 0) _cooldownLeft = max(0, _cooldownLeft - realDt);
    if (_remaining <= 0) return;
    _remaining -= realDt;
    _frozenFor += realDt;
    if (_remaining <= 0) {
      _remaining = 0;
      _frozenFor = 0;
      _cooldownLeft = cooldown;
    }
  }
}

// --------------------------------------------------------------------- pop

/// Squash and stretch: jump to an exaggerated scale, spring back to rest.
///
/// Retriggering restarts the one tween instead of stacking a second, and the
/// scale snaps to exactly 1 at the end so nothing drifts.
class Pop {
  double scaleX = 1;
  double scaleY = 1;

  double _fromX = 1;
  double _fromY = 1;
  double _duration = 0.18;
  double _t = 1;

  bool get resting => _t >= 1;

  /// Keep area roughly constant: stretch one axis, squash the other.
  void trigger({double sx = 1.3, double sy = 0.7, double duration = 0.18}) {
    _fromX = sx;
    _fromY = sy;
    _duration = duration;
    _t = 0;
    scaleX = sx;
    scaleY = sy;
  }

  void update(double dt) {
    if (_t >= 1) return;
    _t = min(1, _t + dt / _duration);
    if (_t >= 1) {
      scaleX = 1;
      scaleY = 1;
      return;
    }
    final e = easeOutBack(_t);
    scaleX = _fromX + (1 - _fromX) * e;
    scaleY = _fromY + (1 - _fromY) * e;
  }
}

// ------------------------------------------------------------------ camera

/// Smooth 2D follow: deadzone, eased look-ahead, exponential smoothing.
///
/// Smoothing uses `1 - exp(-rate * dt)`, which converges the same way at any
/// frame rate. A fixed lerp factor per frame would feel floaty at 30 FPS and
/// snappy at 144. Add shake on top of [x]/[y] afterwards; never feed it back
/// in as the follow target.
class FollowCam {
  FollowCam({
    this.rate = 7,
    this.deadzoneX = 0,
    this.deadzoneY = 0,
    this.lookAhead = 0,
    this.lookRate = 3,
    this.fullLeadSpeed = 200,
  });

  /// Higher is snappier. 5 to 12 is the useful range.
  final double rate;

  /// Half extents of the box the target can move in before the camera moves.
  final double deadzoneX;
  final double deadzoneY;

  /// How far ahead of travel to aim, at or above [fullLeadSpeed].
  final double lookAhead;

  /// How quickly the lead swings round. Low values stop direction flips
  /// from whipping the view.
  final double lookRate;
  final double fullLeadSpeed;

  /// Smoothed camera centre, before shake.
  double x = 0;
  double y = 0;

  double _focusX = 0;
  double _focusY = 0;
  double _leadX = 0;
  double _leadY = 0;

  /// Hard cut, for spawns and teleports. Without it a smoothed camera
  /// slingshots across the level.
  void reset(double targetX, double targetY) {
    x = _focusX = targetX;
    y = _focusY = targetY;
    _leadX = 0;
    _leadY = 0;
  }

  /// Call after the target has moved this frame.
  void update(
    double dt, {
    required double targetX,
    required double targetY,
    double velX = 0,
    double velY = 0,
  }) {
    // Deadzone: the focus only moves by the overflow past the box.
    final overX = targetX - _focusX;
    if (overX.abs() > deadzoneX) _focusX += overX - deadzoneX * overX.sign;
    final overY = targetY - _focusY;
    if (overY.abs() > deadzoneY) _focusY += overY - deadzoneY * overY.sign;

    // Look-ahead, eased toward its goal.
    var goalX = 0.0;
    var goalY = 0.0;
    final speed = sqrt(velX * velX + velY * velY);
    if (lookAhead > 0 && speed > 1) {
      final reach = lookAhead * min(1.0, speed / fullLeadSpeed) / speed;
      goalX = velX * reach;
      goalY = velY * reach;
    }
    final leadT = 1 - exp(-lookRate * dt);
    _leadX += (goalX - _leadX) * leadT;
    _leadY += (goalY - _leadY) * leadT;

    final t = 1 - exp(-rate * dt);
    x += (_focusX + _leadX - x) * t;
    y += (_focusY + _leadY - y) * t;
  }

  /// Keeps the whole view (not just the centre) inside the level rectangle.
  /// An axis where the level is smaller than the view is centred instead.
  void clampView({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required double halfViewW,
    required double halfViewH,
  }) {
    x = _clampAxis(x, minX, maxX, halfViewW);
    y = _clampAxis(y, minY, maxY, halfViewH);
  }

  static double _clampAxis(double v, double lo, double hi, double half) {
    if (hi - lo <= half * 2) return (lo + hi) / 2;
    return v.clamp(lo + half, hi - half);
  }
}
