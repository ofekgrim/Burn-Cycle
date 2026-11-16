import 'dart:math';
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'juice.dart';

/// Fixed-size particle pool.
///
/// Nothing is allocated per burst: a slot is reused once its particle dies,
/// and when the pool is full the oldest slot is overwritten.
class ParticlePool extends Component {
  ParticlePool({this.capacity = 400, this.streaks = false, super.priority})
      : _x = Float32List(capacity),
        _y = Float32List(capacity),
        _vx = Float32List(capacity),
        _vy = Float32List(capacity),
        _life = Float32List(capacity),
        _maxLife = Float32List(capacity),
        _size = Float32List(capacity),
        _drag = Float32List(capacity),
        _gravity = Float32List(capacity),
        _color = Uint32List(capacity);

  final int capacity;

  /// Draw each particle as a short line along its velocity (wind, rain)
  /// instead of a dot.
  final bool streaks;

  final Float32List _x;
  final Float32List _y;
  final Float32List _vx;
  final Float32List _vy;
  final Float32List _life;
  final Float32List _maxLife;
  final Float32List _size;
  final Float32List _drag;
  final Float32List _gravity;
  final Uint32List _color;

  final Random _random = Random();
  final Paint _paint = Paint()..strokeCap = StrokeCap.round;
  int _cursor = 0;

  int get activeCount {
    var n = 0;
    for (var i = 0; i < capacity; i++) {
      if (_life[i] > 0) n++;
    }
    return n;
  }

  void emit(
    double x,
    double y,
    double vx,
    double vy, {
    required Color color,
    double life = 0.5,
    double size = 3,
    double drag = 2,
    double gravity = 0,
  }) {
    final i = _cursor;
    _cursor = (_cursor + 1) % capacity;
    _x[i] = x;
    _y[i] = y;
    _vx[i] = vx;
    _vy[i] = vy;
    _life[i] = life;
    _maxLife[i] = life;
    _size[i] = size;
    _drag[i] = drag;
    _gravity[i] = gravity;
    _color[i] = color.toARGB32();
  }

  /// [count] particles thrown out from one point. [spread] is the full arc
  /// in radians, centred on [direction].
  void burst(
    double x,
    double y, {
    required int count,
    required Color color,
    double speed = 140,
    double life = 0.5,
    double size = 3,
    double direction = 0,
    double spread = 2 * pi,
    double drag = 2.5,
    double gravity = 0,
  }) {
    for (var n = 0; n < count; n++) {
      final angle = direction + (_random.nextDouble() - 0.5) * spread;
      final s = speed * (0.35 + 0.65 * _random.nextDouble());
      emit(
        x,
        y,
        cos(angle) * s,
        sin(angle) * s,
        color: color,
        life: life * (0.6 + 0.4 * _random.nextDouble()),
        size: size * (0.6 + 0.8 * _random.nextDouble()),
        drag: drag,
        gravity: gravity,
      );
    }
  }

  @override
  void update(double dt) {
    for (var i = 0; i < capacity; i++) {
      if (_life[i] <= 0) continue;
      _life[i] -= dt;
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
      final keep = max(0.0, 1 - _drag[i] * dt);
      _vx[i] *= keep;
      _vy[i] = _vy[i] * keep + _gravity[i] * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i < capacity; i++) {
      final life = _life[i];
      if (life <= 0) continue;
      final k = life / _maxLife[i];
      final argb = _color[i];
      final alpha = (((argb >> 24) & 0xFF) * k).round();
      _paint.color = Color.fromARGB(
        alpha,
        (argb >> 16) & 0xFF,
        (argb >> 8) & 0xFF,
        argb & 0xFF,
      );
      if (streaks) {
        _paint.strokeWidth = _size[i];
        canvas.drawLine(
          Offset(_x[i], _y[i]),
          Offset(_x[i] - _vx[i] * 0.035, _y[i] - _vy[i] * 0.035),
          _paint,
        );
      } else {
        canvas.drawCircle(
          Offset(_x[i], _y[i]),
          _size[i] * (0.35 + 0.65 * k),
          _paint,
        );
      }
    }
  }
}

/// Short text that pops in, rises and fades: "+3", "perfect", combo calls.
class FloatingTexts extends Component {
  FloatingTexts({super.priority});

  static const int maxItems = 14;

  final List<_FloatText> _items = [];
  final Random _random = Random();

  int get count => _items.length;

  void spawn(
    String text,
    double x,
    double y, {
    Color color = const Color(0xFFFFFFFF),
    double fontSize = 18,
    double life = 0.9,
    double rise = 44,
  }) {
    if (_items.length >= maxItems) _items.removeAt(0).painter.dispose();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 5)],
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    // A little sideways drift so stacked numbers fan out.
    final drift = (_random.nextDouble() - 0.5) * 36;
    _items.add(_FloatText(painter, x, y, life, rise, drift));
  }

  @override
  void update(double dt) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      item.age += dt;
      if (item.age >= item.life) {
        item.painter.dispose();
        _items.removeAt(i);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    for (final item in _items) {
      final k = (item.age / item.life).clamp(0.0, 1.0);
      final scale = 0.4 + 0.6 * easeOutBack(min(1.0, item.age / 0.16));
      final alpha = k < 0.6 ? 1.0 : 1 - (k - 0.6) / 0.4;
      final w = item.painter.width;
      final h = item.painter.height;
      canvas.save();
      canvas.translate(
        item.x + item.drift * k,
        item.y - item.rise * easeOutCubic(k),
      );
      canvas.scale(scale);
      if (alpha < 1) {
        canvas.saveLayer(
          Rect.fromCenter(center: Offset.zero, width: w + 16, height: h + 16),
          Paint()..color = Color.fromARGB((255 * alpha).round(), 255, 255, 255),
        );
      }
      item.painter.paint(canvas, Offset(-w / 2, -h / 2));
      if (alpha < 1) canvas.restore();
      canvas.restore();
    }
  }
}

class _FloatText {
  _FloatText(this.painter, this.x, this.y, this.life, this.rise, this.drift);

  final TextPainter painter;
  final double x;
  final double y;
  final double life;
  final double rise;
  final double drift;
  double age = 0;
}
