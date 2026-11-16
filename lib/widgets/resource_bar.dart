import 'package:flutter/material.dart';

import '../art/palette.dart';
import '../game/game_state.dart';

/// The four camp resources plus crew size, shown on every non-night screen.
class ResourceBar extends StatelessWidget {
  const ResourceBar({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Resource(emoji: '💧', label: 'מים', value: state.water),
          _Resource(emoji: '⚡', label: 'אנרגיה', value: state.energy),
          _Resource(emoji: '🪵', label: 'חומרים', value: state.materials),
          _Resource(emoji: '✨', label: 'וייב', value: state.vibe),
          _Resource(emoji: '🧑‍🤝‍🧑', label: 'צוות', value: state.crew),
        ],
      ),
    );
  }
}

/// One number that pops and tints briefly whenever it changes.
class _Resource extends StatefulWidget {
  const _Resource({
    required this.emoji,
    required this.label,
    required this.value,
  });

  final String emoji;
  final String label;
  final int value;

  @override
  State<_Resource> createState() => _ResourceState();
}

class _ResourceState extends State<_Resource>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  bool _rose = true;

  @override
  void didUpdateWidget(_Resource old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _rose = widget.value > old.value;
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, _) {
        final k = Curves.easeOutBack.transform(_pop.value);
        final tint = Color.lerp(
          _rose ? Palette.good : Palette.danger,
          theme.colorScheme.onSurface,
          _pop.value,
        );
        // Each number takes a fifth of the bar and shrinks to fit, so large
        // text or big values never overflow a narrow phone.
        return Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Transform.scale(
              scale: 1.35 - 0.35 * k,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.emoji} ${widget.value}',
                    style: theme.textTheme.titleMedium?.copyWith(color: tint),
                  ),
                  Text(widget.label, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
