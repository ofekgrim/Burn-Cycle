import 'package:flutter/material.dart';

import '../camp/camp_game.dart';
import '../game/game_state.dart';
import '../widgets/camp_scaffold.dart';

/// Noon: one event tests the camp while you watch, then the night begins.
class NoonScreen extends StatelessWidget {
  const NoonScreen({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = state.noonEvent!;
    final config = state.nightConfig;
    return CampScaffold(
      state: state,
      mood: CampMood.noon,
      title: 'יום ${state.day} · צהריים',
      bottomHeight: 250,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(event.emoji, style: const TextStyle(fontSize: 44)),
          Text(event.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            event.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 10),
          Text(
            '${state.isManNight ? 'הלילה: ליל המן. ' : 'הלילה: '}'
            '${config.wandererCount} נוודים בפלאיה · '
            '${config.seats} מושבים · '
            '${config.batterySeconds.round()} שניות סוללה',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.startNight,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('לצאת ללילה'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
