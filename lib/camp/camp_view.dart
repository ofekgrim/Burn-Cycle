import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/game_state.dart';
import 'camp_game.dart';

/// Hosts the camp scene and turns taps into cell indices.
class CampView extends StatefulWidget {
  const CampView({
    super.key,
    required this.state,
    required this.mood,
    this.topInset = 0,
    this.bottomInset = 0,
    this.selectedCell,
    this.onCellTap,
  });

  final GameState state;
  final CampMood mood;

  /// Height covered by panels at the top and bottom of the screen.
  final double topInset;
  final double bottomInset;
  final int? selectedCell;
  final void Function(int cell)? onCellTap;

  @override
  State<CampView> createState() => _CampViewState();
}

class _CampViewState extends State<CampView> {
  late final CampGame _game = CampGame(state: widget.state, mood: widget.mood);

  @override
  Widget build(BuildContext context) {
    _game
      ..setInsets(widget.topInset, widget.bottomInset)
      ..selectedCell = widget.selectedCell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.onCellTap == null
          ? null
          : (details) {
              final cell = _game.cellAt(details.localPosition);
              if (cell != null) widget.onCellTap!(cell);
            },
      child: GameWidget(game: _game),
    );
  }
}
