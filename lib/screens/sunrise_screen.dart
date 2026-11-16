import 'package:flutter/material.dart';

import '../camp/camp_game.dart';
import '../game/game_state.dart';
import '../widgets/camp_scaffold.dart';

/// Sunrise: the night's results, then a pick-one-of-three car part draft.
class SunriseScreen extends StatelessWidget {
  const SunriseScreen({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = state.lastNight!;
    final isLastNight = state.day + 1 >= GameState.daysInWeek;
    final firstPickup = night.firstPickupSeconds;
    return CampScaffold(
      state: state,
      mood: CampMood.sunrise,
      title: 'יום ${state.day} · זריחה',
      bottomHeight: 420,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            night.delivered == 0
                ? 'אף אחד לא הגיע לקאמפ הלילה.'
                : '${night.delivered} נוודים הצטרפו לצוות.',
            style: theme.textTheme.titleMedium,
          ),
          if (night.stranded)
            Text(
              'הסוללה נגמרה בדרך. ${night.lost} נוסעים הלכו לאיבוד.',
              textAlign: TextAlign.center,
            ),
          Text(
            'קומבו שיא: ${night.maxCombo} · '
            'ביט: ${night.beatHits}/${night.beatTaps}'
            '${firstPickup == null ? '' : ' · איסוף ראשון: '
                '${firstPickup.toStringAsFixed(1)} שנ׳'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            isLastNight
                ? 'בחרו חלק אחרון לרכב. הבוקר שורפים.'
                : 'בחרו חלק אחד לרכב:',
            style: theme.textTheme.titleSmall,
          ),
          for (var i = 0; i < state.draftOptions.length; i++)
            _DraftCard(
              key: Key('draft-$i'),
              part: state.draftOptions[i],
              index: i,
              onTap: () => state.pickPart(state.draftOptions[i]),
            ),
          if (state.parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'על הרכב: ${state.parts.map((p) => p.emoji).join(' ')}',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

/// A draft option that pops in, one after the other.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    super.key,
    required this.part,
    required this.index,
    required this.onTap,
  });

  final CarPart part;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + 110 * index),
      curve: Interval(index * 0.2, 1, curve: Curves.easeOutBack),
      builder: (context, k, child) => Opacity(
        opacity: k.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.8 + 0.2 * k, child: child),
      ),
      child: Card(
        child: ListTile(
          leading: Text(part.emoji, style: const TextStyle(fontSize: 32)),
          title: Text(part.name),
          subtitle: Text(part.description),
          onTap: onTap,
        ),
      ),
    );
  }
}
