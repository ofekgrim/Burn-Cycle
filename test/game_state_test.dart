import 'package:burn_cycle/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GameState newState() => GameState(seed: 1);

  test('starts on day 1 morning with a small crew', () {
    final state = newState();
    expect(state.day, 1);
    expect(state.phase, Phase.morning);
    expect(state.crew, 2);
    expect(state.buildings, isEmpty);
  });

  test('building spends materials and anchoring costs one more', () {
    final state = newState();
    final before = state.materials;
    expect(state.build(0, BuildingType.shade, anchored: false), isTrue);
    expect(state.materials, before - 2);
    expect(state.vibe, 1);
    expect(state.build(1, BuildingType.kitchen, anchored: true), isTrue);
    expect(state.materials, before - 2 - 4);
    expect(state.buildings[1]!.anchored, isTrue);
  });

  test('cannot build on an occupied cell or without materials', () {
    final state = newState();
    state.build(0, BuildingType.shade, anchored: false);
    expect(state.build(0, BuildingType.kitchen, anchored: false), isFalse);
    state.materials = 0;
    expect(state.build(2, BuildingType.kitchen, anchored: false), isFalse);
  });

  test('a full day loop moves to the next morning and grows the crew', () {
    final state = newState();
    state.endMorning();
    expect(state.phase, Phase.noon);
    state.startNight();
    expect(state.phase, Phase.night);
    state.finishNight(const NightResult(
      delivered: 4,
      lost: 0,
      maxCombo: 10,
      stranded: false,
    ));
    expect(state.phase, Phase.sunrise);
    expect(state.crew, 6);
    expect(state.vibe, 4); // 4 ~/ 2 + 10 ~/ 5
    expect(state.draftOptions, hasLength(3));
    final seats = state.car.seats;
    final part = state.draftOptions.first;
    state.pickPart(part);
    expect(state.day, 2);
    expect(state.phase, Phase.morning);
    expect(state.parts, [part]);
    expect(state.car.seats, greaterThanOrEqualTo(seats));
  });

  test('anchored buildings survive the big storm', () {
    final state = newState();
    state.materials = 100;
    state.build(0, BuildingType.shade, anchored: true);
    state.build(1, BuildingType.kitchen, anchored: true);
    state.day = GameState.bigStormDay;
    state.endMorning();
    expect(state.buildings, hasLength(2));
  });

  test('a storm reports what it tore down and spares anchored buildings', () {
    final state = newState();
    state.materials = 100;
    for (var cell = 0; cell < 12; cell++) {
      state.build(cell, BuildingType.shade, anchored: cell.isEven);
    }
    state.day = GameState.bigStormDay;
    state.endMorning();
    final destroyed = state.noonEvent!.destroyed;
    expect(state.noonEvent!.kind, NoonKind.bigStorm);
    expect(destroyed, isNotEmpty);
    expect(destroyed.keys.every((cell) => cell.isOdd), isTrue);
    expect(state.buildings.length, 12 - destroyed.length);
  });

  test('the same seed deals the same week however you play', () {
    List<String> play(int seed, {required bool busy}) {
      final state = GameState(seed: seed)..water = 1000;
      final log = <String>[];
      for (var day = 1; day < GameState.daysInWeek; day++) {
        if (busy) {
          state.materials = 50;
          state.build(day, BuildingType.kitchen, anchored: true);
          state.build(day + 10, BuildingType.generator, anchored: false);
        }
        state.endMorning();
        log.add(state.noonEvent!.kind.name);
        state.startNight();
        log.add('night ${state.nightConfig.seed}');
        state.finishNight(NightResult(
          delivered: busy ? 4 : 0,
          lost: 0,
          maxCombo: busy ? 12 : 0,
          stranded: !busy,
        ));
        log.add(state.draftOptions.map((p) => p.name).join(','));
        state.pickPart(state.draftOptions[busy ? 2 : 0]);
      }
      return log;
    }

    expect(play(42, busy: true), play(42, busy: false));
    expect(play(42, busy: true), isNot(play(43, busy: true)));
  });

  test('the week ends in a burn that pays out embers', () {
    final state = newState();
    state.water = 1000;
    for (var day = 1; day < GameState.daysInWeek; day++) {
      state.endMorning();
      state.startNight();
      state.finishNight(const NightResult(
        delivered: 1,
        lost: 0,
        maxCombo: 0,
        stranded: false,
      ));
      state.pickPart(state.draftOptions.first);
    }
    expect(state.phase, Phase.burn);
    expect(state.endedEarly, isFalse);
    expect(state.lastEmbers, state.emberValue);
    expect(state.totalEmbers, state.lastEmbers);
    state.startNextYear();
    expect(state.year, 2);
    expect(state.day, 1);
    expect(state.phase, Phase.morning);
  });

  test('running out of water ends the run early for half the embers', () {
    final state = newState();
    state.water = 0;
    state.endMorning();
    // Day 1 is always a gift; make sure it cannot rescue the run.
    state.water = 0;
    state.startNight();
    state.finishNight(const NightResult(
      delivered: 0,
      lost: 0,
      maxCombo: 0,
      stranded: false,
    ));
    state.pickPart(state.draftOptions.first);
    expect(state.phase, Phase.burn);
    expect(state.endedEarly, isTrue);
    expect(state.lastEmbers, state.emberValue ~/ 2);
  });
}
