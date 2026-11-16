# Burn Cycle (prototype)

Roguelite prototype in Flutter + Flame: build a desert camp by day, drive an
art car by night to fill it with people, burn everything on day 7 and start
the next year with embers.

## Run it

```bash
flutter pub get
flutter run -d chrome                 # web
flutter run -d <simulator or phone>   # iOS / Android
flutter test                          # rules, feel, and a bot that plays a whole year
flutter test --platform chrome        # the same suite compiled to JavaScript
flutter test integration_test/full_run_test.dart -d <device>   # the bot, on a real device
```

Flame 1.38 needs Flutter 3.41+. With Xcode 27 the iOS target must be 15.0 or
later (already set in `ios/`). `flutter build ios --simulator` fails on
Flutter 3.41.3 with Xcode 27.2 (a `lipo -verify_arch` incompatibility);
`flutter run -d <simulator>` works.

## How to play

1. **Morning** - tap an empty cell to build. Anchored buildings cost one more
   material and survive storms. Tap an unanchored building to anchor it later.
2. **Noon** - one event hits the camp (a big storm is guaranteed on day 5).
3. **Night** - drag to steer the art car. Touch wanderers to pick them up and
   drive through the camp circle to drop them off. Tap with a second finger
   (or press Space) when the ring lands on the car for a speed boost.
   Arrow keys / WASD also steer. The night ends when the battery runs out;
   if that happens away from camp, half the passengers are lost.
4. **Sunrise** - pick one of three car parts.
5. **Day 7** - the burn. Camp value turns into embers, which give extra
   starting materials next year.

## Layout

| Path | What it holds |
| --- | --- |
| `lib/game/game_state.dart` | All rules and run state (plain Dart, unit-tested) |
| `lib/game/rng.dart` | Seeded PRNG that gives the same rolls on web and native |
| `lib/fx/juice.dart` | Game feel in plain Dart: shake, hit-stop, squash and stretch, follow camera |
| `lib/fx/particles.dart` | Pooled particles and floating text |
| `lib/camp/` | The isometric camp scene, shared by morning, noon, sunrise and the burn |
| `lib/night/night_game.dart` | The night drive: car, wanderers, camp, beat, landmarks |
| `lib/art/palette.dart` | Colour roles used by every scene |
| `lib/screens/`, `lib/widgets/` | Flutter panels and HUD over the scenes |
| `test/support/playthrough.dart` | The bot that plays a year through the real UI |

## Feel and comfort

Every event fires one feedback tier (small, medium, large) that sets shake,
hit-stop and particles together. The tune button on the morning screen has a
shake-strength slider and a reduce-flashing switch. Press the backquote key
during the night for a playtest readout (speed, beat timing, hit rate).

## Not built yet

- Wanderer types and synergies (crew is a plain number for now)
- The ten-principles perk tree, car chassis, camp themes
- Saving between sessions (embers live in memory only)
- Sound; the beat is a visual ring on a fixed 100 BPM clock
- Android has platform files but has not been built or run
