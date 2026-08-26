// emulator_session_screen.dart -- The emulator's own screen: the family
// pattern shared with Retro-Amiga, Retro-Saturn, Retro-C64, Retro-Dosbox
// and Retro-Spectrum. Launching pushes this route fullscreen; everything a
// player needs mid-game lives here, and both ways out land back on the
// workbench in exactly one place.
//
// A corner handle opens the pause menu (machine paused, picture dimmed):
// Resume, Save and exit, Close. The right-hand rail carries the in-game
// tools that used to sit on the workbench's bottom bar -- disk swap,
// screen fill, ST keyboard, reset -- as labelled buttons.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/game_entry.dart';
import '../ffi/atarist_core.dart';
import '../services/app_prefs.dart';
import '../theme/retro_atarist_theme.dart';
import 'emulator_screen.dart';

/// How a session ended, from the workbench's point of view.
///
/// Both exits save your position (closing a title must never be more
/// destructive than pausing one); the distinction is only what the
/// workbench offers next -- [paused] leads with the Resume card.
enum SessionExit { paused, closed }

class EmulatorSessionScreen extends StatefulWidget {
  final AtariStCore core;
  final GameEntry entry;

  /// Whether protected-format floppy timing is on, for the drive readout.
  final bool accurateFloppy;

  /// How the on-screen stick decides to appear, and the live controller
  /// state that `auto` watches.
  final OnScreenControls onScreenControls;
  final ValueListenable<bool> controllerConnected;

  /// Puts a disk in a drive of the running machine -- owned by the
  /// workbench, which knows the both-drives ejection rule.
  final void Function(int drive, String path) onInsertDisk;

  /// The engine-side half of Save and exit: capture the resume point and
  /// stop the core. Returns false if the position could not be saved, in
  /// which case this screen stays put rather than silently losing the game.
  final Future<bool> Function() onSaveAndExit;

  /// The engine-side half of Close: capture (closing saves too) and stop.
  final Future<void> Function() onClose;

  const EmulatorSessionScreen({
    super.key,
    required this.core,
    required this.entry,
    required this.accurateFloppy,
    required this.onScreenControls,
    required this.controllerConnected,
    required this.onInsertDisk,
    required this.onSaveAndExit,
    required this.onClose,
  });

  @override
  State<EmulatorSessionScreen> createState() => _EmulatorSessionScreenState();
}

class _EmulatorSessionScreenState extends State<EmulatorSessionScreen> {
  /// Session state that used to live on the workbench.
  bool _showKeyboard = false;
  bool _screenFill = false;
  int _diskInDriveA = 0;

  /// Session override for the on-screen pad. Null follows the Input
  /// setting (auto hides it while a controller is connected); the rail's
  /// Pad button pins it on or off for this session -- a manual choice
  /// wins, the model Retro-Dosbox proved out.
  bool? _padOverride;

  /// Layout mode: the pad's clusters drag instead of press, and moves are
  /// remembered.
  bool _editingLayout = false;

  /// The pause menu: machine stopped, picture dimmed, choices pinned up.
  bool _menuOpen = false;

  /// Whether the corner handle and rail are on screen. They hide a few
  /// seconds after the last touch: a 4:3 machine on a widescreen handheld
  /// has no width to lend to furniture that is only occasionally wanted.
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  /// Guards the two exits against double taps.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // The session owns the whole screen: hide the system bars for the
    // duration and give them back on the way out. Sticky, because an edge
    // swipe on a handheld is easy to do by accident mid-game.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(AppPrefs.screenFill().then((fill) {
      if (mounted) setState(() => _screenFill = fill);
    }));
    _restartControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_menuOpen) setState(() => _controlsVisible = false);
    });
  }

  void _wakeControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _restartControlsTimer();
  }

  void _setMenu(bool open) {
    setState(() {
      _menuOpen = open;
      _controlsVisible = true;
    });
    // The menu freezes the machine for real -- audio included -- rather
    // than dimming a game that plays on underneath.
    widget.core.setPaused(open);
    if (!open) _restartControlsTimer();
  }

  Future<void> _saveAndExit() async {
    if (_leaving) return;
    _leaving = true;
    final saved = await widget.onSaveAndExit();
    if (!mounted) return;
    if (!saved) {
      _leaving = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save your position.'),
      ));
      return;
    }
    Navigator.of(context).pop(SessionExit.paused);
  }

  Future<void> _close() async {
    if (_leaving) return;
    _leaving = true;
    await widget.onClose();
    if (!mounted) return;
    Navigator.of(context).pop(SessionExit.closed);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // The machine. EmulatorScreen still draws the framebuffer, the
            // ST keyboard and the on-screen stick; the session chrome lives
            // out here on top of it. The controller listenable drives the
            // auto mode live, so plugging a pad in mid-game hides the
            // on-screen stick without a rebuild from above.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _wakeControls(),
                child: ValueListenableBuilder<bool>(
                  valueListenable: widget.controllerConnected,
                  builder: (context, padConnected, _) => EmulatorScreen(
                    core: widget.core,
                    title: entry.title,
                    disks: entry.disks,
                    accurateFloppy: widget.accurateFloppy,
                    showOnScreenControls: _padOverride ??
                        switch (widget.onScreenControls) {
                          OnScreenControls.always => true,
                          OnScreenControls.never => false,
                          OnScreenControls.auto => !padConnected,
                        },
                    editingLayout: _editingLayout,
                    showKeyboard: _showKeyboard,
                    fillScreen: _screenFill,
                    onExit: () => unawaited(_close()),
                    onInsertDisk: widget.onInsertDisk,
                  ),
                ),
              ),
            ),
            if (_menuOpen) ...[
              // Dim the frozen picture. Tapping the picture resumes --
              // the cheapest way back into the game is the game itself.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setMenu(false),
                  child: Container(color: const Color(0xB3000000)),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ResumeButton(onTap: () => _setMenu(false)),
                    const SizedBox(height: 28),
                    _MenuChoice(
                      icon: Icons.bookmark_add_outlined,
                      label: 'Save and exit',
                      detail:
                          'Keep your place and return to the workbench',
                      onTap: () => unawaited(_saveAndExit()),
                    ),
                    const SizedBox(height: 12),
                    _MenuChoice(
                      icon: Icons.close,
                      label: 'Close',
                      detail: 'End the session (your position is still '
                          'saved) and return to the workbench',
                      onTap: () => unawaited(_close()),
                    ),
                  ],
                ),
              ),
            ],
            // The in-game tool rail, down the right edge where the thumb
            // already is. Hidden while the menu is up -- the menu IS the
            // controls then.
            if (!_menuOpen)
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Center(child: _toolRail()),
                  ),
                ),
              ),
            // The corner handle: the one control that is always reachable.
            // ☰ opens the pause menu; while the menu is up it reads ▶ and
            // resumes, so the same corner always undoes itself.
            Positioned(
              left: 4,
              top: 4,
              child: AnimatedOpacity(
                opacity: (_controlsVisible || _menuOpen) ? 1 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: const Color(0x66000000),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      _wakeControls();
                      _setMenu(!_menuOpen);
                    },
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        _menuOpen ? Icons.play_arrow : Icons.menu,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolRail() {
    final entry = widget.entry;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Multi-disk titles get the swap first: "insert disk 2" mid-load is
        // the moment this rail exists for.
        if (entry.disks.length > 1)
          _RailTool(
            icon: Icons.album,
            label: 'Disk ${_diskInDriveA + 1}',
            tooltip: 'Disk ${_diskInDriveA + 1} of ${entry.disks.length}'
                ' -- tap for the next one',
            onTap: () {
              _wakeControls();
              final next = (_diskInDriveA + 1) % entry.disks.length;
              widget.onInsertDisk(0, entry.disks[next]);
              setState(() => _diskInDriveA = next);
            },
          ),
        _RailTool(
          // The ST is a 4:3 machine and a handheld is not, so a faithful
          // picture leaves a quarter of the screen black. Which of those
          // two annoyances you prefer is genuinely a matter of taste, so
          // it is a toggle rather than a decision made for the user.
          icon: _screenFill ? Icons.fit_screen : Icons.aspect_ratio,
          label: 'Fill',
          lit: _screenFill,
          tooltip: _screenFill
              ? "Keep the ST's 4:3 shape"
              : 'Stretch to fill the screen',
          onTap: () {
            _wakeControls();
            final next = !_screenFill;
            setState(() => _screenFill = next);
            unawaited(AppPrefs.setScreenFill(next));
          },
        ),
        _RailTool(
          icon: Icons.videogame_asset,
          label: 'Pad',
          lit: _padOverride ?? false,
          tooltip: 'On-screen joystick',
          onTap: () {
            _wakeControls();
            setState(() {
              // Cycle: follow-the-setting -> pinned on -> pinned off.
              _padOverride = switch (_padOverride) {
                null => true,
                true => false,
                false => null,
              };
              if (_padOverride == false) _editingLayout = false;
            });
          },
        ),
        _RailTool(
          icon: _editingLayout ? Icons.check : Icons.open_with,
          label: 'Layout',
          lit: _editingLayout,
          tooltip: _editingLayout
              ? 'Finish moving controls'
              : 'Move the on-screen controls',
          onTap: () {
            _wakeControls();
            setState(() => _editingLayout = !_editingLayout);
          },
        ),
        _RailTool(
          icon: Icons.keyboard,
          label: 'Keys',
          lit: _showKeyboard,
          tooltip: 'ST keyboard',
          onTap: () {
            _wakeControls();
            setState(() => _showKeyboard = !_showKeyboard);
          },
        ),
        _RailTool(
          icon: Icons.restart_alt,
          label: 'Reset',
          tooltip: 'Reset the machine',
          onTap: () {
            _wakeControls();
            widget.core.reset();
          },
        ),
      ],
    );
  }
}

/// One labelled tool on the session rail: a 34px circle with its name under
/// it, matching the rest of the Retro-* family's rails.
class _RailTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool lit;
  final VoidCallback onTap;

  const _RailTool({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.lit = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: lit
                  ? RetroAtariStColors.accentAtariRed
                  : const Color(0x66000000),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: tooltip,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                shadows: [Shadow(blurRadius: 3, color: Colors.black)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big centred resume control on the pause menu.
class _ResumeButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ResumeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RetroAtariStColors.accentAtariRed,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Icon(Icons.play_arrow, color: Colors.white, size: 44),
        ),
      ),
    );
  }
}

/// A pause-menu row: icon, name, and a line saying what it will do.
class _MenuChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  const _MenuChoice({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE0181C20),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
