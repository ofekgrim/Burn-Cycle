import 'package:flutter/material.dart';
import 'package:burn_cycle/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playthrough.dart';

void main() {
  Future<void> at(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a whole year plays through on a phone-sized screen',
      (tester) async {
    await at(tester, const Size(393, 852));
    expect(await playFullYear(tester), GameState.daysInWeek - 1,
        reason: 'seed 7 with a kitchen a day should reach the burn');
  });

  testWidgets('a whole year plays through on a desktop browser window',
      (tester) async {
    await at(tester, const Size(1400, 870));
    expect(await playFullYear(tester), GameState.daysInWeek - 1,
        reason: 'seed 7 with a kitchen a day should reach the burn');
  });

  testWidgets('a whole year plays through on a small landscape window',
      (tester) async {
    await at(tester, const Size(800, 600));
    expect(await playFullYear(tester), GameState.daysInWeek - 1,
        reason: 'seed 7 with a kitchen a day should reach the burn');
  });
}
