import 'package:flutter/material.dart';

import '../art/palette.dart';
import '../camp/camp_game.dart';
import '../game/game_state.dart';
import '../widgets/camp_scaffold.dart';

/// Day 7: the camp burns down in front of the crew and turns into embers
/// for next year.
class BurnScreen extends StatelessWidget {
  const BurnScreen({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CampScaffold(
      state: state,
      mood: CampMood.burn,
      title: state.endedEarly ? 'נגמרו המים' : 'השריפה',
      showResources: false,
      bottomHeight: 250,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            state.endedEarly
                ? 'הקאמפ התפרק ביום ${state.day}, לפני סוף השבוע. '
                    'קיבלתם חצי מהגחלים.'
                : 'שנה ${state.year} נשרפה. '
                    '${state.crew} אנשי צוות, '
                    '${state.buildings.length} מבנים, '
                    '${state.vibe} וייב.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // The payoff counts up while the camp burns.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: state.lastEmbers.toDouble()),
            duration: const Duration(milliseconds: 2600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              '+${value.round()} גחלים',
              style:
                  theme.textTheme.displaySmall?.copyWith(color: Palette.ember),
            ),
          ),
          Text('סך הכול: ${state.totalEmbers}'),
          Text(
            'seed ${state.runSeed}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.white.withAlpha(110)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.startNextYear,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('לשנה הבאה'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
