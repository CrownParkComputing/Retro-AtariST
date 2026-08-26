// The running machine: picture, input, and the control strip.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_prefs.dart';
import '../data/st_scancodes.dart';
import '../ffi/atarist_core.dart';
import '../theme/retro_atarist_theme.dart';
import '../widgets/movable_control.dart';
import '../widgets/framebuffer_view.dart';

class EmulatorScreen extends StatefulWidget {
  final AtariStCore core;
  final String title;

  /// Called when the user exits the session, so the workbench can stop the
  /// core and go back to the library.
  final VoidCallback onExit;

  /// Offered when the running title has more than one disk.
  final List<String> disks;
  final void Function(int drive, String path)? onInsertDisk;

  /// True when this title is running with cycle-accurate FDC timing, i.e. it
  /// is a protected original (.stx/.ipf).
  ///
  /// Surfaced because the honest behaviour looks exactly like a hang: a
  /// protected original loads in real 1988-1991 time, which is forty seconds
  /// to a minute of black screen with the drive light flickering. Without
  /// saying so, the first thing anyone does is press Exit.
  final bool accurateFloppy;

  /// Whether the ST keyboard overlay is showing. Owned by the workbench,
  /// because the button that toggles it now lives in the bar beneath the
  /// window rather than inside this screen.
  final bool showKeyboard;

  /// Stretch the picture to fill the space rather than keeping the ST's 4:3
  /// shape. Toggled from the session bar.
  final bool fillScreen;

  /// Whether to draw the on-screen joystick over the picture.
  ///
  /// False when a real controller is connected (see AppPrefs.onScreenControls).
  /// The pad covers a corner of a 320x200 picture, which is a real cost on a
  /// small screen for controls nobody is touching.
  final bool showOnScreenControls;

  /// Layout mode: the pad's clusters drag instead of press, and moves are
  /// remembered -- the family's contract (see AppPrefs.controlPositions).
  final bool editingLayout;

  const EmulatorScreen({
    super.key,
    required this.core,
    required this.title,
    required this.onExit,
    this.disks = const <String>[],
    this.onInsertDisk,
    this.accurateFloppy = false,
    this.showOnScreenControls = true,
    this.editingLayout = false,
    this.showKeyboard = false,
    this.fillScreen = false,
  });

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  final FocusNode _focus = FocusNode();

  /// Centre of each on-screen control as fractions of the play area.
  Map<String, Offset> _controlPositions = const {};

  /// Current joystick mask, so the on-screen stick and a hardware gamepad can
  /// both contribute without either clobbering the other's bits.
  int _joyMask = 0;


  /// When this session started, for the protected-original loading hint.
  late final DateTime _startedAt = DateTime.now();

  /// How long the protected-original notice stays up.
  ///
  /// Long enough to be read, short enough to be gone before the game draws
  /// anything. It only has to answer one question -- "is this black screen
  /// broken?" -- and once that is answered it is just a banner sitting over
  /// the picture.
  static const Duration _loadingHintDuration = Duration(seconds: 5);

  bool get _showLoadingHint =>
      widget.accurateFloppy &&
      DateTime.now().difference(_startedAt) < _loadingHintDuration;

  @override
  void initState() {
    super.initState();
    AppPrefs.controlPositions().then((stored) {
      if (mounted && stored.isNotEmpty) {
        setState(() => _controlPositions = stored);
      }
    });
    // Requested after the first frame: asking during initState attaches the
    // node before the focus scope exists and the keyboard silently goes
    // nowhere.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(covariant EmulatorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A direction held on the on-screen stick at the moment a controller is
    // plugged in would otherwise stay held forever: the pad vanishes and its
    // pointer-up never arrives, leaving the ST joystick deflected with no
    // visible control to release it.
    if (oldWidget.showOnScreenControls &&
        !widget.showOnScreenControls &&
        _joyMask != 0) {
      _joyMask = 0;
      widget.core.joystick(0, 0);
      widget.core.joystick(1, 0);
    }
  }

  @override
  void dispose() {
    // A modifier latched down when the keyboard is torn down must not stay
    // held in the machine forever.
    for (final code in {..._armedModifiers, ..._lockedModifiers}) {
      widget.core.keyEvent(code, false);
    }
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final scancode = StScancode.fromPhysical[event.physicalKey];
    if (scancode == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      widget.core.keyEvent(scancode, true);
    } else if (event is KeyUpEvent) {
      widget.core.keyEvent(scancode, false);
    }
    // KeyRepeatEvent is deliberately dropped: the ST's own IKBD generates
    // repeats at its own rate, and forwarding the host's as well gives a
    // doubled, uneven repeat in anything that reads the keyboard directly.
    return KeyEventResult.handled;
  }

  void _setJoyBit(int bit, bool on) {
    final next = on ? (_joyMask | bit) : (_joyMask & ~bit);
    if (next == _joyMask) return;
    _joyMask = next;
    // Both ports. ST games read port 1 and the mouse lives on port 0, but a
    // handful of titles disagree, and driving both costs nothing.
    widget.core.joystick(0, _joyMask);
    widget.core.joystick(1, _joyMask);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _screen()),
                if (_showLoadingHint)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 12,
                    child: Center(child: _loadingHint()),
                  ),
                if (widget.showOnScreenControls || widget.editingLayout)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children:
                            _padControls(constraints.biggest),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.showKeyboard) _onScreenKeyboard(),
        ],
      ),
    );
  }

  Widget _loadingHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: RetroAtariStColors.accentAtariRed),
      ),
      child: const Text(
        'Protected original: loading takes up to a minute, as it did on real '
        'hardware. A black screen here is normal.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _screen() {
    return GestureDetector(
      // Relative motion, because the ST mouse IS relative -- there is no
      // absolute position to jump to, and a tap-to-place pointer would fight
      // whatever position the ST thinks it is at.
      onPanUpdate: (d) => widget.core.mouseMotion(
        d.delta.dx.round(),
        d.delta.dy.round(),
      ),
      onTapDown: (_) => widget.core.mouseButton(0, true),
      onTapUp: (_) => widget.core.mouseButton(0, false),
      onTapCancel: () => widget.core.mouseButton(0, false),
      onLongPressStart: (_) => widget.core.mouseButton(1, true),
      onLongPressEnd: (_) => widget.core.mouseButton(1, false),
      child: FramebufferView(
        core: widget.core,
        fillScreen: widget.fillScreen,
      ),
    );
  }

  /// The d-pad and the FIRE button, each movable in layout mode and
  /// remembered -- the family's fraction-of-play-area contract. A d-pad
  /// rather than an analogue stick, still: the ST port is four digital
  /// direction lines and one button, so an analogue stick would only be
  /// inventing a precision the hardware cannot carry.
  List<Widget> _padControls(Size area) {
    Widget movable(String id, Offset fallback, String label, Widget child) {
      return MovableControl(
        area: area,
        fraction: _controlPositions[id] ?? fallback,
        editing: widget.editingLayout,
        label: label,
        onMoved: (f) =>
            setState(() => _controlPositions = {..._controlPositions, id: f}),
        onMoveEnd: () {
          final f = _controlPositions[id];
          if (f != null) AppPrefs.setControlPosition(id, f);
        },
        child: child,
      );
    }

    return [
      movable('dpad', const Offset(0.12, 0.78), 'D-pad', _dpadCluster()),
      movable('fire', const Offset(0.88, 0.78), 'Fire', _fireButton()),
    ];
  }

  Widget _padButton(String label, int bit, {double size = 44}) {
    final active = (_joyMask & bit) != 0;
    return Listener(
      onPointerDown: (_) => _setJoyBit(bit, true),
      onPointerUp: (_) => _setJoyBit(bit, false),
      onPointerCancel: (_) => _setJoyBit(bit, false),
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? RetroAtariStColors.accentAtariRed.withValues(alpha: 0.8)
              : Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  Widget _dpadCluster() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _padButton('↑', StJoyBits.up),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _padButton('←', StJoyBits.left),
            const SizedBox(width: 48),
            _padButton('→', StJoyBits.right),
          ],
        ),
        _padButton('↓', StJoyBits.down),
      ],
    );
  }

  Widget _fireButton() => _padButton('FIRE', StJoyBits.fire, size: 60);

  /// Modifier latching. The ST keyboard needs SHIFT-letter and
  /// ALT-combinations, and on glass a held modifier is a two-finger job.
  /// Tap cycles the modifier: off -> armed (releases after the next
  /// ordinary key) -> locked (stays until tapped off) -- the model
  /// Retro-Dosbox's PC keyboard proved out.
  static const Set<int> _modifierCodes = {
    StScancode.leftShift,
    StScancode.rightShift,
    StScancode.control,
    StScancode.alternate,
  };
  final Set<int> _armedModifiers = {};
  final Set<int> _lockedModifiers = {};

  void _tapModifier(int code) {
    setState(() {
      if (_lockedModifiers.contains(code)) {
        _lockedModifiers.remove(code);
        widget.core.keyEvent(code, false);
      } else if (_armedModifiers.contains(code)) {
        _armedModifiers.remove(code);
        _lockedModifiers.add(code);
        // Already down from arming; stays down.
      } else {
        _armedModifiers.add(code);
        widget.core.keyEvent(code, true);
      }
    });
  }

  void _releaseArmedModifiers() {
    if (_armedModifiers.isEmpty) return;
    for (final code in _armedModifiers) {
      widget.core.keyEvent(code, false);
    }
    setState(() => _armedModifiers.clear());
  }

  /// The ST keyboard as ONE board. The rows used to be independent
  /// horizontal scrollers, so they slid out of alignment and the board
  /// never read as a keyboard; now the whole board scales down to the
  /// width it is given, rows locked together.
  Widget _onScreenKeyboard() {
    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final row in StScancode.onScreenRows)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (label, code) in row) _key(label, code),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _key(String label, int code) {
    final isModifier = _modifierCodes.contains(code);
    final armed = _armedModifiers.contains(code);
    final locked = _lockedModifiers.contains(code);
    if (isModifier) {
      return GestureDetector(
        onTap: () => _tapModifier(code),
        child: Container(
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: locked
                ? RetroAtariStColors.accentAtariRed
                : RetroAtariStColors.cardFill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: armed
                  ? RetroAtariStColors.accentAtariRed
                  : RetroAtariStColors.cardStroke,
              width: armed ? 2 : 1,
            ),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.white)),
        ),
      );
    }
    return Listener(
      // Listener, not a button: a key must go down when touched and up when
      // released, and a Button's onTap fires once on release with no down
      // half at all.
      onPointerDown: (_) => widget.core.keyEvent(code, true),
      onPointerUp: (_) {
        widget.core.keyEvent(code, false);
        // A one-shot modifier covers exactly one ordinary keypress.
        _releaseArmedModifiers();
      },
      onPointerCancel: (_) {
        widget.core.keyEvent(code, false);
        _releaseArmedModifiers();
      },
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: RetroAtariStColors.cardFill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: RetroAtariStColors.cardStroke),
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.white)),
      ),
    );
  }

}
