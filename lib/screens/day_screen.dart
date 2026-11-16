import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../camp/camp_game.dart';
import '../widgets/camp_scaffold.dart';

/// Morning: tap a tile in the camp scene to build on it, then end the
/// morning.
class DayScreen extends StatefulWidget {
  const DayScreen({super.key, required this.state});

  final GameState state;

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  int? _selected;

  GameState get state => widget.state;

  Future<void> _onCellTap(int cell) async {
    final building = state.buildings[cell];
    if (building != null && building.anchored) return;
    setState(() => _selected = cell);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => building == null
          ? _BuildSheet(state: state, cell: cell)
          : _AnchorSheet(state: state, cell: cell),
    );
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    return CampScaffold(
      state: state,
      mood: CampMood.morning,
      title: 'שנה ${state.year} · יום ${state.day} מתוך '
          '${GameState.daysInWeek} · בוקר',
      headerLines: state.morningLog,
      headerAction: IconButton(
        tooltip: 'הגדרות',
        icon: const Icon(Icons.tune),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => _FeelSheet(state: state),
        ),
      ),
      selectedCell: _selected,
      onCellTap: _onCellTap,
      bottomHeight: 76,
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: state.endMorning,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('לסיים את הבוקר'),
          ),
        ),
      ),
    );
  }
}

/// Comfort options for screen shake and pulsing light.
class _FeelSheet extends StatefulWidget {
  const _FeelSheet({required this.state});

  final GameState state;

  @override
  State<_FeelSheet> createState() => _FeelSheetState();
}

class _FeelSheetState extends State<_FeelSheet> {
  @override
  Widget build(BuildContext context) {
    final feel = widget.state.feel;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'רעידת מסך: ${(feel.shakeStrength * 100).round()}%',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              value: feel.shakeStrength,
              onChanged: (v) => setState(() => feel.shakeStrength = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('להפחית הבהובים'),
              value: feel.reduceFlashing,
              onChanged: (v) => setState(() => feel.reduceFlashing = v),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildSheet extends StatelessWidget {
  const _BuildSheet({required this.state, required this.cell});

  final GameState state;
  final int cell;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // A Column, not a lazy ListView: there are only five rows, and every
      // one should exist even when large text pushes some off screen.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'מה לבנות? יש לכם ${state.materials} חומרים. '
                'מבנה מעוגן עולה חומר אחד נוסף ושורד סופות.',
              ),
            ),
            for (final def in buildingDefs)
              ListTile(
                leading: Text(def.emoji, style: const TextStyle(fontSize: 28)),
                title: Text(def.name),
                subtitle: Text(def.effect),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: Key('build-${def.type.name}'),
                      onPressed: state.canBuild(cell, def.type, anchored: false)
                          ? () => _build(context, def.type, anchored: false)
                          : null,
                      child: Text('לבנות (${def.cost})'),
                    ),
                    TextButton(
                      key: Key('build-anchored-${def.type.name}'),
                      onPressed: state.canBuild(cell, def.type, anchored: true)
                          ? () => _build(context, def.type, anchored: true)
                          : null,
                      child: Text(
                        'מעוגן (${def.cost + GameState.anchorCost})',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _build(
    BuildContext context,
    BuildingType type, {
    required bool anchored,
  }) {
    state.build(cell, type, anchored: anchored);
    Navigator.of(context).pop();
  }
}

class _AnchorSheet extends StatelessWidget {
  const _AnchorSheet({required this.state, required this.cell});

  final GameState state;
  final int cell;

  @override
  Widget build(BuildContext context) {
    final building = state.buildings[cell]!;
    final def = defOf(building.type);
    final canAnchor = state.materials >= GameState.anchorCost;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${def.emoji} ${def.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(def.effect),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: canAnchor
                  ? () {
                      state.anchor(cell);
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('לעגן (חומר אחד)'),
            ),
          ],
        ),
      ),
    );
  }
}
