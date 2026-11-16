import 'package:flutter/material.dart';

import '../art/palette.dart';
import '../camp/camp_game.dart';
import '../camp/camp_view.dart';
import '../game/game_state.dart';
import 'resource_bar.dart';

/// Shared layout of every daytime screen: the camp scene fills the screen,
/// a header panel sits on top and an optional panel at the bottom.
class CampScaffold extends StatelessWidget {
  const CampScaffold({
    super.key,
    required this.state,
    required this.mood,
    required this.title,
    this.headerLines = const [],
    this.headerAction,
    this.showResources = true,
    this.bottom,
    this.bottomHeight = 84,
    this.selectedCell,
    this.onCellTap,
  });

  final GameState state;
  final CampMood mood;
  final String title;
  final List<String> headerLines;
  final Widget? headerAction;
  final bool showResources;

  /// Panel pinned to the bottom. It scrolls if it does not fit.
  final Widget? bottom;

  /// Roughly how tall [bottom] is, so the camp is laid out above it.
  final double bottomHeight;
  final int? selectedCell;
  final void Function(int cell)? onCellTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final headerH = 52.0 + (showResources ? 70 : 0) + 17.0 * headerLines.length;
    final panelH = bottomHeight.clamp(0.0, screenH * 0.62);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CampView(
              state: state,
              mood: mood,
              topInset: media.padding.top + headerH,
              bottomInset: media.padding.bottom + panelH,
              selectedCell: selectedCell,
              onCellTap: onCellTap,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                GamePanel(
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          SizedBox(width: 40, child: headerAction),
                        ],
                      ),
                      if (showResources) ResourceBar(state: state),
                      for (final line in headerLines)
                        Text(
                          line,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                if (bottom != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: screenH * 0.62,
                      maxWidth: 560,
                    ),
                    child: GamePanel(
                      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: SingleChildScrollView(child: bottom),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark translucent card that keeps text readable over the bright playa.
class GamePanel extends StatelessWidget {
  const GamePanel({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: child,
    );
  }
}
