import 'package:burn_cycle/fx/juice.dart';
import 'package:burn_cycle/game/rng.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shake', () {
    test('trauma drains to zero within 1 / decay seconds and recentres', () {
      final shake = Shake(decay: 1.2)..add(1);
      var moved = false;
      for (var t = 0.0; t < 1 / 1.2 + 0.02; t += 1 / 60) {
        shake.update(1 / 60);
        if (shake.offsetX != 0) moved = true;
      }
      expect(moved, isTrue);
      expect(shake.trauma, 0);
      expect(shake.offsetX, 0);
      expect(shake.offsetY, 0);
      expect(shake.roll, 0);
    });

    test('hits add up to a cap and strength 0 keeps the camera still', () {
      final shake = Shake()
        ..add(0.7)
        ..add(0.7);
      expect(shake.trauma, 1);
      shake.update(1 / 60, strength: 0);
      expect(shake.offsetX, 0);
      expect(shake.roll, 0);
    });
  });

  group('hit-stop', () {
    test('two hits 30 ms apart restore time once, after the longer stop', () {
      final stop = HitStop()..trigger(0.12);
      var clock = 0.0;
      void step(double dt) {
        stop.update(dt);
        clock += dt;
      }

      step(0.03);
      stop.trigger(0.05); // overlapping, shorter
      expect(stop.timeScale, lessThan(1));
      while (stop.active) {
        step(0.005);
      }
      expect(stop.timeScale, 1);
      expect(clock, closeTo(0.12, 0.011));
    });

    test('a hit every frame cannot freeze the game', () {
      final stop = HitStop();
      var frozen = 0.0;
      var longest = 0.0;
      var run = 0.0;
      for (var i = 0; i < 600; i++) {
        stop.trigger(0.12);
        stop.update(1 / 60);
        if (stop.active) {
          frozen += 1 / 60;
          run += 1 / 60;
          if (run > longest) longest = run;
        } else {
          run = 0;
        }
      }
      expect(longest, lessThanOrEqualTo(0.15 + 1 / 60));
      expect(frozen, lessThan(10 * 0.65));
    });
  });

  test('a pop ends at exactly its rest scale, even when retriggered', () {
    final pop = Pop()..trigger(sx: 1.3, sy: 0.7);
    pop.update(0.05);
    pop.trigger(sx: 1.3, sy: 0.7);
    var overshot = false;
    for (var i = 0; i < 30; i++) {
      pop.update(1 / 60);
      if (pop.scaleX < 1) overshot = true;
    }
    expect(overshot, isTrue, reason: 'ease-out-back should overshoot');
    expect(pop.scaleX, 1);
    expect(pop.scaleY, 1);
    expect(pop.resting, isTrue);
  });

  group('follow camera', () {
    double lagAt(double dt) {
      final cam = FollowCam(rate: 8)..reset(0, 0);
      var x = 0.0;
      for (var t = 0.0; t < 2; t += dt) {
        x += 300 * dt;
        cam.update(dt, targetX: x, targetY: 0);
      }
      return x - cam.x;
    }

    test('trails the target by about the same distance at 30 and 144 FPS', () {
      final slow = lagAt(1 / 30);
      final fast = lagAt(1 / 144);
      expect(slow, closeTo(33, 2));
      expect(fast, closeTo(37, 2));
      expect((slow - fast).abs(), lessThan(6));
    });

    test('ignores movement inside the deadzone and leads travel outside it',
        () {
      final cam = FollowCam(deadzoneX: 20, deadzoneY: 20, lookAhead: 80)
        ..reset(0, 0);
      for (var i = 0; i < 60; i++) {
        cam.update(1 / 60, targetX: 15, targetY: -10);
      }
      expect(cam.x, 0);
      expect(cam.y, 0);
      var x = 15.0;
      for (var i = 0; i < 240; i++) {
        x += 200 / 60;
        cam.update(1 / 60, targetX: x, targetY: 0, velX: 200);
      }
      expect(cam.x, greaterThan(x), reason: 'camera should look ahead');
    });

    test('clamps the view, and centres a level smaller than the view', () {
      final cam = FollowCam()..reset(950, 0);
      cam.clampView(
        minX: -1000,
        maxX: 1000,
        minY: -100,
        maxY: 100,
        halfViewW: 200,
        halfViewH: 300,
      );
      expect(cam.x, 800);
      expect(cam.y, 0);
    });
  });

  test('seeded rng repeats, and nearby seeds do not share a first roll', () {
    final a = SeededRng(7);
    final b = SeededRng(7);
    expect(
      [for (var i = 0; i < 8; i++) a.nextInt(1000)],
      [for (var i = 0; i < 8; i++) b.nextInt(1000)],
    );
    final firsts = {
      for (var day = 1; day <= 40; day++)
        SeededRng(SeededRng.mix(1, day, 1)).nextInt(4),
    };
    expect(firsts, {0, 1, 2, 3});
    // Pinned values: the web build must produce these same numbers.
    final pinned = SeededRng(12345);
    expect([pinned.nextInt(1000), pinned.nextInt(1000), pinned.nextInt(1000)],
        pinnedRolls);
  });
}

/// Filled in from a VM run; `flutter test --platform chrome` checks the
/// JavaScript build against it.
const pinnedRolls = [292, 31, 640];
