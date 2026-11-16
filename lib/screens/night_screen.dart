import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_state.dart';
import '../night/night_game.dart';

/// Night: hosts the Flame game and translates touch, mouse and keyboard
/// input into steering and beat taps.
///
/// Controls:
/// - Drag anywhere to steer (a virtual joystick appears under the finger).
/// - Tap with a second finger, or press Space, on the beat for a boost.
/// - Arrow keys / WASD also steer.
class NightScreen extends StatefulWidget {
  const NightScreen({super.key, required this.state});

  final GameState state;

  @override
  State<NightScreen> createState() => _NightScreenState();
}

class _NightScreenState extends State<NightScreen> {
  static const double _stickRadius = 60;

  late final NightGame _game;
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  bool _debug = false;

  int? _steerPointer;
  Offset _stickOrigin = Offset.zero;
  Offset _stickOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _game = NightGame(
      config: widget.state.nightConfig,
      onFinished: widget.state.finishNight,
      feel: widget.state.feel,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- pointers

  void _onPointerDown(PointerDownEvent event) {
    if (_steerPointer == null) {
      setState(() {
        _steerPointer = event.pointer;
        _stickOrigin = event.localPosition;
        _stickOffset = Offset.zero;
      });
      _game.steer.setZero();
    } else {
      _game.tapBeat();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _steerPointer) return;
    var offset = event.localPosition - _stickOrigin;
    if (offset.distance > _stickRadius) {
      offset = offset / offset.distance * _stickRadius;
    }
    setState(() => _stickOffset = offset);
    _game.steer.setValues(offset.dx / _stickRadius, offset.dy / _stickRadius);
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _steerPointer) return;
    setState(() {
      _steerPointer = null;
      _stickOffset = Offset.zero;
    });
    _applyKeys();
  }

  // ------------------------------------------------------------- keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _game.tapBeat();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.backquote) {
        setState(() => _debug = !_debug);
        return KeyEventResult.handled;
      }
      _keys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _keys.remove(event.logicalKey);
    }
    if (_steerPointer == null) _applyKeys();
    return KeyEventResult.handled;
  }

  void _applyKeys() {
    double x = 0;
    double y = 0;
    if (_keys.contains(LogicalKeyboardKey.arrowLeft) ||
        _keys.contains(LogicalKeyboardKey.keyA)) {
      x -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowRight) ||
        _keys.contains(LogicalKeyboardKey.keyD)) {
      x += 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowUp) ||
        _keys.contains(LogicalKeyboardKey.keyW)) {
      y -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowDown) ||
        _keys.contains(LogicalKeyboardKey.keyS)) {
      y += 1;
    }
    _game.steer.setValues(x, y);
    if (x != 0 && y != 0) _game.steer.normalize();
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: Stack(
            children: [
              Positioned.fill(
                // GameWidget swallows key events when it holds focus, so the
                // Focus above keeps it instead.
                child: GameWidget(game: _game, autofocus: false),
              ),
              if (_steerPointer != null) ..._buildStick(),
              Positioned.fill(
                child: SafeArea(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _game.hud,
                    builder: (context, _, __) => _Hud(
                      game: _game,
                      day: widget.state.day,
                      debug: _debug,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStick() {
    // Positioned (unlike PositionedDirectional) uses physical left/top, so
    // pointer coordinates map directly even though the app is RTL.
    return [
      Positioned(
        left: _stickOrigin.dx - _stickRadius,
        top: _stickOrigin.dy - _stickRadius,
        child: IgnorePointer(
          child: Container(
            width: _stickRadius * 2,
            height: _stickRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(20),
              border: Border.all(color: Colors.white.withAlpha(60)),
            ),
          ),
        ),
      ),
      Positioned(
        left: _stickOrigin.dx + _stickOffset.dx - 22,
        top: _stickOrigin.dy + _stickOffset.dy - 22,
        child: IgnorePointer(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFB347).withAlpha(170),
            ),
          ),
        ),
      ),
    ];
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.game, required this.day, required this.debug});

  final NightGame game;
  final int day;

  /// Playtest readout, toggled with the backquote key.
  final bool debug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                game.config.isManNight ? 'ליל המן' : 'לילה $day',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(width: 12),
              const Text('🔋'),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: game.batteryFraction,
                    minHeight: 10,
                    color: game.batteryFraction < 0.25
                        ? const Color(0xFFFF5A5A)
                        : const Color(0xFF6BFF8A),
                    backgroundColor: Colors.white.withAlpha(30),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Stat('ברכב: ${game.passengers}/${game.config.seats}'),
              _Stat('בקאמפ: ${game.delivered}'),
              _Stat('בפלאיה: ${game.wanderers.length}'),
              _Stat('קומבו: ${game.combo}'),
            ],
          ),
          if (debug)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                'speed ${game.car.velocity.length.round()} px/s · '
                'tap ${(game.lastTapOffset * 1000).round()} ms · '
                'beat ${game.beatHits}/${game.beatTaps} · '
                'first pickup '
                '${game.firstPickupSeconds?.toStringAsFixed(1) ?? '-'} s · '
                'trauma ${game.shake.trauma.toStringAsFixed(2)} · '
                'time x${game.hitStop.timeScale}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white.withAlpha(170)),
              ),
            ),
          const Spacer(),
          if (game.atCamp && game.delivered > 0 && !game.finished)
            Center(
              child: FilledButton.tonal(
                onPressed: game.endNightAtCamp,
                child: const Text('לסיים את הלילה בקאמפ'),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'גררו כדי לנהוג · הקישו באצבע שנייה (או רווח) כשהטבעת נוגעת ברכב',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.white.withAlpha(150)),
          ),
        ],
      ),
    );
  }
}

/// One HUD counter. The four share the row equally and shrink to fit.
class _Stat extends StatelessWidget {
  const _Stat(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(text)),
    );
  }
}
