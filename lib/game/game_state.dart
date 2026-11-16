import 'dart:math';

import 'package:flutter/foundation.dart';

import '../fx/juice.dart';
import 'rng.dart';

/// The phases of a single in-game day, plus the final burn.
enum Phase { morning, noon, night, sunrise, burn }

enum BuildingType { shade, kitchen, generator, soundStage, workshop }

class BuildingDef {
  const BuildingDef({
    required this.type,
    required this.name,
    required this.emoji,
    required this.cost,
    required this.effect,
    this.vibe = 0,
  });

  final BuildingType type;
  final String name;
  final String emoji;

  /// Cost in materials. Anchoring costs [GameState.anchorCost] more.
  final int cost;
  final String effect;

  /// Vibe granted once, when the building is placed.
  final int vibe;
}

const List<BuildingDef> buildingDefs = [
  BuildingDef(
    type: BuildingType.shade,
    name: 'צל',
    emoji: '⛱️',
    cost: 2,
    vibe: 1,
    effect: '+1 וייב, מגן על הצוות מגל חום',
  ),
  BuildingDef(
    type: BuildingType.kitchen,
    name: 'מטבח',
    emoji: '🍲',
    cost: 3,
    effect: '+2 מים ביום',
  ),
  BuildingDef(
    type: BuildingType.generator,
    name: 'גנרטור',
    emoji: '⚡',
    cost: 3,
    effect: '+2 אנרגיה ביום',
  ),
  BuildingDef(
    type: BuildingType.soundStage,
    name: 'במת סאונד',
    emoji: '🔊',
    cost: 4,
    vibe: 3,
    effect: '+3 וייב, ‎−1 אנרגיה ביום',
  ),
  BuildingDef(
    type: BuildingType.workshop,
    name: 'סדנה',
    emoji: '🔧',
    cost: 4,
    effect: '+20% סוללה לרכב בלילה',
  ),
];

BuildingDef defOf(BuildingType type) =>
    buildingDefs.firstWhere((d) => d.type == type);

class PlacedBuilding {
  PlacedBuilding(this.type, {this.anchored = false});

  final BuildingType type;
  bool anchored;
}

/// Everything about the art car that persists between nights of one year.
class CarStats {
  int seats = 4;
  double batteryMul = 1;
  double speedMul = 1;
  double lightBonus = 0;

  /// Seconds either side of the beat that still count as a hit.
  double beatWindow = 0.12;
}

class CarPart {
  CarPart({
    required this.name,
    required this.emoji,
    required this.description,
    required this.apply,
  });

  final String name;
  final String emoji;
  final String description;
  final void Function(CarStats stats) apply;
}

final List<CarPart> partPool = [
  CarPart(
    name: 'ספסל נוסף',
    emoji: '🛋️',
    description: '+1 מושב ברכב',
    apply: (s) => s.seats += 1,
  ),
  CarPart(
    name: 'סוללה נוספת',
    emoji: '🔋',
    description: '+15% זמן סוללה',
    apply: (s) => s.batteryMul += 0.15,
  ),
  CarPart(
    name: 'מנוע משופר',
    emoji: '🏎️',
    description: '+10% מהירות',
    apply: (s) => s.speedMul += 0.10,
  ),
  CarPart(
    name: 'שרשרת לדים',
    emoji: '💡',
    description: 'רדיוס אור גדול יותר',
    apply: (s) => s.lightBonus += 30,
  ),
  CarPart(
    name: 'סאבוופר',
    emoji: '🥁',
    description: 'חלון ביט רחב יותר, קל יותר לפגוע',
    apply: (s) => s.beatWindow += 0.03,
  ),
];

/// What the night scene needs in order to run.
class NightConfig {
  const NightConfig({
    required this.seats,
    required this.batterySeconds,
    required this.speedMul,
    required this.lightRadius,
    required this.beatWindow,
    required this.wandererCount,
    this.seed = 0,
    this.isManNight = false,
  });

  final int seats;
  final double batterySeconds;
  final double speedMul;
  final double lightRadius;
  final double beatWindow;
  final int wandererCount;

  /// Where the wanderers and art pieces stand tonight.
  final int seed;

  /// The Man burns tonight: twice the crowd.
  final bool isManNight;
}

class NightResult {
  const NightResult({
    required this.delivered,
    required this.lost,
    required this.maxCombo,
    required this.stranded,
    this.beatTaps = 0,
    this.beatHits = 0,
    this.firstPickupSeconds,
  });

  final int delivered;
  final int lost;
  final int maxCombo;

  /// True when the battery died away from camp.
  final bool stranded;

  // Playtest readouts. They change no rule; the sunrise screen shows them so
  // a tester can report how the drive went.
  final int beatTaps;
  final int beatHits;

  /// Seconds until the first wanderer was picked up, null if nobody was.
  final double? firstPickupSeconds;
}

enum NoonKind { gift, storm, bigStorm, heat, rangers }

class NoonEvent {
  const NoonEvent(
    this.kind,
    this.emoji,
    this.title,
    this.description, {
    this.destroyed = const {},
  });

  final NoonKind kind;
  final String emoji;
  final String title;
  final String description;

  /// Buildings the event tore down, by cell, so the camp scene can show
  /// them blowing away.
  final Map<int, BuildingType> destroyed;
}

/// All run state and rules. Pure Dart apart from [ChangeNotifier], so it can
/// be unit-tested without a widget tree.
///
/// Randomness is seeded: [runSeed] plus the year, the day and a purpose id
/// pick an independent stream for every roll. The same seed therefore deals
/// the same events and the same drafts however the player builds or drives.
class GameState extends ChangeNotifier {
  GameState({int? seed})
      : runSeed = seed ?? (DateTime.now().millisecondsSinceEpoch & 0x3FFFFFFF) {
    _resetYear();
  }

  static const int gridSize = 6;
  static const int daysInWeek = 7;
  static const int anchorCost = 1;
  static const int bigStormDay = 5;
  static const int manNightDay = 6;

  // One id per independent random stream.
  static const int _rollEvent = 1;
  static const int _rollGift = 2;
  static const int _rollStorm = 3;
  static const int _rollDraft = 4;
  static const int _rollNight = 5;

  final int runSeed;

  // Profile state: survives the burn.
  int year = 1;
  int totalEmbers = 0;
  final FeelSettings feel = FeelSettings();

  // Run state: reset every year.

  late int day;
  late Phase phase;
  late int water;
  late int energy;
  late int materials;
  late int vibe;
  late int crew;
  late Map<int, PlacedBuilding> buildings;
  late CarStats car;
  late List<CarPart> parts;

  /// What changed at the start of this morning, shown on the day screen.
  List<String> morningLog = const [];
  NoonEvent? noonEvent;
  NightResult? lastNight;
  List<CarPart> draftOptions = const [];

  int lastEmbers = 0;
  bool endedEarly = false;

  void _resetYear() {
    day = 1;
    phase = Phase.morning;
    water = 12;
    energy = 2;
    // A small head start from previous years' embers.
    materials = 6 + totalEmbers ~/ 10;
    vibe = 0;
    crew = 2;
    buildings = {};
    car = CarStats();
    parts = [];
    noonEvent = null;
    lastNight = null;
    draftOptions = const [];
    endedEarly = false;
    morningLog = year == 1
        ? const ['הגעתם לפלאיה. הקימו צל ותתחילו לבנות.']
        : ['שנה $year. הגחלים של שנים קודמות נתנו לכם חומרים נוספים.'];
  }

  int _subSeed(int purpose, [int extra = 0]) =>
      SeededRng.mix(runSeed, year * 16 + day, purpose, extra);

  Random _rng(int purpose) => SeededRng(_subSeed(purpose));

  int countOf(BuildingType type) =>
      buildings.values.where((b) => b.type == type).length;

  int get waterPerDay => (crew + 1) ~/ 2;

  /// Embers this camp would be worth if it burned right now.
  int get emberValue => vibe + 2 * crew + 3 * buildings.length;

  // ---------------------------------------------------------------- morning

  int costOf(BuildingType type, {required bool anchored}) =>
      defOf(type).cost + (anchored ? anchorCost : 0);

  bool canBuild(int cell, BuildingType type, {required bool anchored}) =>
      phase == Phase.morning &&
      !buildings.containsKey(cell) &&
      materials >= costOf(type, anchored: anchored);

  bool build(int cell, BuildingType type, {required bool anchored}) {
    if (!canBuild(cell, type, anchored: anchored)) return false;
    materials -= costOf(type, anchored: anchored);
    buildings[cell] = PlacedBuilding(type, anchored: anchored);
    vibe += defOf(type).vibe;
    notifyListeners();
    return true;
  }

  bool anchor(int cell) {
    final building = buildings[cell];
    if (phase != Phase.morning ||
        building == null ||
        building.anchored ||
        materials < anchorCost) {
      return false;
    }
    materials -= anchorCost;
    building.anchored = true;
    notifyListeners();
    return true;
  }

  void endMorning() {
    if (phase != Phase.morning) return;
    noonEvent = _rollNoonEvent();
    phase = Phase.noon;
    notifyListeners();
  }

  // ------------------------------------------------------------------- noon

  NoonEvent _rollNoonEvent() {
    if (day == 1) return _gift();
    if (day == bigStormDay) {
      final destroyed = _storm(0.8);
      return NoonEvent(
        NoonKind.bigStorm,
        '🌪️',
        'הסופה הגדולה',
        destroyed.isEmpty
            ? 'הקאמפ עמד בסופה. שום מבנה לא נפגע.'
            : 'הסופה פירקה ${destroyed.length} מבנים לא מעוגנים.',
        destroyed: destroyed,
      );
    }
    switch (_rng(_rollEvent).nextInt(4)) {
      case 0:
        final destroyed = _storm(0.4);
        return NoonEvent(
          NoonKind.storm,
          '💨',
          'סופת אבק',
          destroyed.isEmpty
              ? 'אבק בכל מקום, אבל המבנים שרדו.'
              : 'הרוח פירקה ${destroyed.length} מבנים לא מעוגנים.',
          destroyed: destroyed,
        );
      case 1:
        if (countOf(BuildingType.shade) > 0) {
          return const NoonEvent(
            NoonKind.heat,
            '🥵',
            'גל חום',
            'הצל הציל את הצוות. לא אבדו מים.',
          );
        }
        final loss = min(water, waterPerDay);
        water -= loss;
        return NoonEvent(
          NoonKind.heat,
          '🥵',
          'גל חום',
          'אין צל בקאמפ. הצוות שתה עוד $loss מים.',
        );
      case 2:
        return _gift();
      default:
        if (vibe >= 5) {
          materials += 2;
          return const NoonEvent(
            NoonKind.rangers,
            '🤠',
            'ביקור ריינג׳רים',
            'הריינג׳רים התרשמו מהקאמפ והשאירו 2 חומרים.',
          );
        }
        return const NoonEvent(
          NoonKind.rangers,
          '🤠',
          'ביקור ריינג׳רים',
          'בדיקה שגרתית. הכול תקין.',
        );
    }
  }

  NoonEvent _gift() {
    if (_rng(_rollGift).nextBool()) {
      water += 3;
      return const NoonEvent(
        NoonKind.gift,
        '🎁',
        'מתנה מהשכנים',
        'הקאמפ השכן הביא 3 מים.',
      );
    }
    materials += 3;
    return const NoonEvent(
      NoonKind.gift,
      '🎁',
      'מתנה מהשכנים',
      'הקאמפ השכן הביא 3 חומרים.',
    );
  }

  /// Tears down each unanchored building with probability [chance] and
  /// returns what was lost. Every cell rolls on its own stream, so whether
  /// a spot is hit today does not depend on what else was built.
  Map<int, BuildingType> _storm(double chance) {
    final destroyed = <int, BuildingType>{};
    final cells = buildings.keys.toList()..sort();
    for (final cell in cells) {
      final roll = SeededRng(_subSeed(_rollStorm, cell)).nextDouble();
      if (!buildings[cell]!.anchored && roll < chance) {
        destroyed[cell] = buildings[cell]!.type;
      }
    }
    for (final entry in destroyed.entries) {
      buildings.remove(entry.key);
      vibe = max(0, vibe - defOf(entry.value).vibe);
    }
    return destroyed;
  }

  void startNight() {
    if (phase != Phase.noon) return;
    phase = Phase.night;
    notifyListeners();
  }

  // ------------------------------------------------------------------ night

  bool get isManNight => day == manNightDay;

  NightConfig get nightConfig {
    final workshops = countOf(BuildingType.workshop);
    final wanderers = (8 + vibe) * (isManNight ? 2 : 1);
    return NightConfig(
      seats: car.seats,
      batterySeconds:
          (45 + 5 * energy) * car.batteryMul * (1 + 0.2 * workshops),
      speedMul: car.speedMul,
      lightRadius: 170 + car.lightBonus,
      beatWindow: car.beatWindow,
      wandererCount: min(40, wanderers),
      seed: _subSeed(_rollNight),
      isManNight: isManNight,
    );
  }

  void finishNight(NightResult result) {
    if (phase != Phase.night) return;
    lastNight = result;
    crew += result.delivered;
    vibe += result.delivered ~/ 2 + result.maxCombo ~/ 5;
    final pool = List<CarPart>.of(partPool)..shuffle(_rng(_rollDraft));
    draftOptions = pool.take(3).toList();
    phase = Phase.sunrise;
    notifyListeners();
  }

  // ---------------------------------------------------------------- sunrise

  void pickPart(CarPart part) {
    if (phase != Phase.sunrise) return;
    part.apply(car);
    parts.add(part);
    day += 1;
    if (day >= daysInWeek) {
      _burn(early: false);
    } else {
      _beginMorning();
    }
    notifyListeners();
  }

  void _beginMorning() {
    final log = <String>[];

    final waterIn = 2 * countOf(BuildingType.kitchen);
    final energyIn = 2 * countOf(BuildingType.generator);
    final energyOut = countOf(BuildingType.soundStage);
    final materialsIn = 2 + crew ~/ 2;

    water += waterIn - waterPerDay;
    energy += energyIn - energyOut;
    materials += materialsIn;

    log.add('הצוות שתה $waterPerDay מים'
        '${waterIn > 0 ? ', המטבחים הוסיפו $waterIn' : ''}.');
    log.add('הצוות אסף $materialsIn חומרים.');
    if (energy < 0) {
      energy = 0;
      vibe = max(0, vibe - 1);
      log.add('אין מספיק אנרגיה לבמות. הוייב ירד ב-1.');
    }
    if (day == bigStormDay) {
      log.add('תחזית: סופה גדולה בצהריים. עגנו את המבנים.');
    }
    if (day == manNightDay) {
      log.add('הלילה שורפים את המן. הפלאיה תהיה מלאה בנוודים.');
    }

    if (water < 0) {
      water = 0;
      _burn(early: true);
      return;
    }
    morningLog = log;
    phase = Phase.morning;
  }

  // ------------------------------------------------------------------- burn

  void _burn({required bool early}) {
    endedEarly = early;
    lastEmbers = early ? emberValue ~/ 2 : emberValue;
    totalEmbers += lastEmbers;
    phase = Phase.burn;
  }

  void startNextYear() {
    if (phase != Phase.burn) return;
    year += 1;
    _resetYear();
    notifyListeners();
  }
}
