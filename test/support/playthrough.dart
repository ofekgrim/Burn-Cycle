import 'package:burn_cycle/camp/camp_game.dart';
import 'package:burn_cycle/game/game_state.dart';
import 'package:burn_cycle/main.dart';
import 'package:burn_cycle/night/night_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plays one whole year through the real UI: taps tiles, drags to steer,
/// taps the beat with a second pointer, drafts parts and watches the burn.
/// Used by the widget test (VM and Chrome) and by the on-device
/// integration test.
Future<int> playFullYear(WidgetTester tester) async {
  await tester.pumpWidget(const BurnCycleApp(seed: 7));
  await _settle(tester);
  expect(find.textContaining('יום 1'), findsOneWidget);

  var daysPlayed = 0;
  for (var day = 1; day < GameState.daysInWeek; day++) {
    // A camp that runs out of water burns early. That is a legal ending.
    if (find.text('לסיים את הבוקר').evaluate().isEmpty) break;
    daysPlayed = day;
    await _morning(tester, day);
    await _tapText(tester, 'לסיים את הבוקר');
    expect(find.textContaining('צהריים'), findsOneWidget);
    await _pumpFor(tester, 600);
    await _tapText(tester, 'לצאת ללילה');
    await _night(tester);
    expect(find.textContaining('זריחה'), findsOneWidget);
    await _pumpFor(tester, 700);
    await tester.tap(find.byKey(const Key('draft-0')));
    await _settle(tester);
  }

  expect(find.text('לשנה הבאה'), findsOneWidget);
  expect(find.textContaining('גחלים'), findsWidgets);
  // Let the camp burn down.
  await _pumpFor(tester, 4000);
  await _tapText(tester, 'לשנה הבאה');
  expect(find.textContaining('שנה 2 ·'), findsOneWidget);
  return daysPlayed;
}

Future<void> _settle(WidgetTester tester) => _pumpFor(tester, 450);

/// The scenes animate forever, so pumpAndSettle would never return.
Future<void> _pumpFor(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await _settle(tester);
}

CampGame _camp(WidgetTester tester) => tester
    .widget<GameWidget<CampGame>>(find.byType(GameWidget<CampGame>))
    .game!;

Future<void> _morning(WidgetTester tester, int day) async {
  final camp = _camp(tester);
  final box = tester.getTopLeft(find.byType(GameWidget<CampGame>));
  final state = camp.state;
  // Build on a fresh tile each day: a shade and a generator first, then a
  // kitchen a day so the growing crew does not run out of water.
  final plan = day == 1
      ? ['build-shade', 'build-anchored-generator']
      : ['build-anchored-kitchen', 'build-kitchen'];
  var cell = day * 5;
  for (final key in plan) {
    while (state.buildings.containsKey(cell)) {
      cell++;
    }
    final before = state.buildings.length;
    await tester.tapAt(box + camp.cellCenter(cell));
    await _settle(tester);
    final button = find.byKey(Key(key));
    expect(button, findsOneWidget, reason: 'build sheet should be open');
    if (tester.widget<TextButton>(button).onPressed != null) {
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await _settle(tester);
      expect(state.buildings.length, before + 1);
    } else {
      // Cannot afford it: close the sheet.
      await tester.tapAt(const Offset(20, 20));
      await _settle(tester);
    }
  }
}

Future<void> _night(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  final finder = find.byType(GameWidget<NightGame>);
  expect(finder, findsOneWidget);
  final game = tester.widget<GameWidget<NightGame>>(finder).game!;
  final center = tester.getCenter(finder);
  final seats = game.config.seats;

  final stick = await tester.startGesture(center);
  var lastBeat = -1;
  var steps = 0;
  while (!game.finished && steps < 6000) {
    steps++;
    final goHome = game.passengers >= seats ||
        game.wanderers.isEmpty ||
        (game.passengers > 0 && game.batteryFraction < 0.4);
    var tx = 0.0;
    var ty = 0.0;
    if (!goHome) {
      var best = double.infinity;
      for (final w in game.wanderers) {
        final d = w.position.distanceTo(game.car.position);
        if (d < best) {
          best = d;
          tx = w.position.x;
          ty = w.position.y;
        }
      }
    }
    final dx = tx - game.car.position.x;
    final dy = ty - game.car.position.y;
    final d = Offset(dx, dy).distance;
    if (d > 1) await stick.moveTo(center + Offset(dx, dy) / d * 60);

    // Tap a second finger on the beat.
    final beat = (game.beatClock / NightGame.beatPeriod).round();
    final off = (game.beatClock - beat * NightGame.beatPeriod).abs();
    if (beat != lastBeat && off < 0.03) {
      lastBeat = beat;
      await tester.tapAt(center + const Offset(90, 120));
    }

    if (game.atCamp && game.delivered >= 3 && game.passengers == 0) {
      await stick.up();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('לסיים את הלילה בקאמפ'));
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(game.finished, isTrue, reason: 'the night should end');
  expect(game.delivered, greaterThan(0), reason: 'the bot should deliver');
  expect(game.beatHits, greaterThan(0), reason: 'beat taps should land');
  // Outro, then the sunrise screen.
  await _pumpFor(tester, 1600);
}
