import 'package:flutter/material.dart';

import 'game/game_state.dart';
import 'screens/burn_screen.dart';
import 'screens/day_screen.dart';
import 'screens/night_screen.dart';
import 'screens/noon_screen.dart';
import 'screens/sunrise_screen.dart';

void main() {
  runApp(const BurnCycleApp());
}

class BurnCycleApp extends StatefulWidget {
  const BurnCycleApp({super.key, this.seed});

  /// Fixed run seed, for tests and (later) daily runs. Random when null.
  final int? seed;

  @override
  State<BurnCycleApp> createState() => _BurnCycleAppState();
}

class _BurnCycleAppState extends State<BurnCycleApp> {
  late final GameState _state = GameState(seed: widget.seed);

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burn Cycle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A1A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1C1210),
        useMaterial3: true,
      ),
      // Hebrew UI: everything, including dialogs and sheets, is RTL.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          switch (_state.phase) {
            case Phase.morning:
              return DayScreen(state: _state);
            case Phase.noon:
              return NoonScreen(state: _state);
            case Phase.night:
              // A fresh key per night so the Flame game is rebuilt each time.
              return NightScreen(
                key: ValueKey('night-${_state.year}-${_state.day}'),
                state: _state,
              );
            case Phase.sunrise:
              return SunriseScreen(state: _state);
            case Phase.burn:
              return BurnScreen(state: _state);
          }
        },
      ),
    );
  }
}
