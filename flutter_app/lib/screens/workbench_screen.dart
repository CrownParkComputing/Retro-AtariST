// The shell: rail + content panel + status bar.
//
// Tabs swap inside the panel, they are never pushed as routes -- the family's
// workbench is one screen with a changing middle, and a navigator stack here
// would give every settings tab a back button that means something different
// from the rail.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/game_entry.dart';
import '../ffi/atarist_core.dart';
import '../services/app_prefs.dart';
import '../services/gamepad_service.dart';
import '../services/games_folder.dart';
import '../services/library_scanner.dart';
import '../services/session_store.dart';
import '../services/tos_store.dart';
import '../theme/retro_atarist_theme.dart';
import '../widgets/sidebar.dart';
import '../widgets/sidebar_style.dart';
import 'about_screen.dart';
import 'compliance_screen.dart';
import 'emulator_session_screen.dart';
import 'input_settings_screen.dart';
import 'library_grid.dart';
import 'machine_settings_screen.dart';
import 'media_settings_screen.dart';
import 'paths_settings_screen.dart';

/// The rail's destinations.
///
/// [group] sorts them into bands: where you go, how it is set up, and
/// everything else. The last group is pinned to the bottom of the rail, which
/// is where About has always lived and where a band that drifts as the list
/// above it grows would stop being a landmark.
enum WorkbenchTab {
  games('\u{1F4BE}', 'Games', 0),
  running('\u{25B6}\u{FE0F}', 'Running', 0),
  resume('\u{23EF}\u{FE0F}', 'Resume', 0),
  machine('\u{1F5A5}\u{FE0F}', 'Machine', 1),
  media('\u{1F4C0}', 'Media', 1),
  input('\u{1F579}\u{FE0F}', 'Input', 1),
  paths('\u{1F4C2}', 'Paths', 1),
  compliance('\u{2705}', 'Compliance', 2),
  about('\u{2139}\u{FE0F}', 'About', 2);

  final String icon;
  final String title;
  final int group;

  const WorkbenchTab(this.icon, this.title, this.group);
}

class WorkbenchScreen extends StatefulWidget {
  final AtariStCore core;
  final bool usingStub;
  final String? appBuild;
  final String workDir;
  final String tosDir;
  final VoidCallback? onRunSetupWizard;

  const WorkbenchScreen({
    super.key,
    required this.core,
    required this.workDir,
    required this.tosDir,
    this.usingStub = false,
    this.appBuild,
    this.onRunSetupWizard,
  });

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen>
    with WidgetsBindingObserver {
  WorkbenchTab _tab = WorkbenchTab.games;

  List<GameEntry> _entries = const [];
  List<String> _unreadable = const [];
  String _gamesFolder = '';
  bool _scanning = true;

  StMachineConfig _config = const StMachineConfig();
  bool _complianceMode = false;
  List<TosRom> _roms = const [];
  List<String> _volumeChoices = const [];

  GameEntry? _running;
  String? _error;

  /// Whether the rail is collapsed. The bar along the bottom owns the toggle,
  /// deliberately: it is the only way back once the rail is gone, so it
  /// cannot live inside the rail it controls.
  bool _sidebarHidden = false;

  /// Saved positions, keyed by library path -- one per title, so closing one
  /// game never costs you the position of another.
  Map<String, ResumePoint> _resumePoints = const {};

  /// The most recently put-down title, which is what the Resume tab offers.
  ResumePoint? _resumePoint;

  /// Refreshes the status readouts while a machine is running.
  ///
  /// Without it the fps and the paused indicator only update when something
  /// else happens to call setState, so they show whatever was true at the
  /// last interaction. That is worse than showing nothing: a frozen "49 fps"
  /// beside a machine that had in fact been paused for two minutes is exactly
  /// the reading that sends you looking for a bug in the emulator.
  Timer? _statusTicker;

  /// External controllers. Owned here rather than by the emulator screen so
  /// detection keeps running while the user is in the library -- otherwise
  /// the on-screen stick decides whether to appear based on a poll that has
  /// only just started, and flickers in for the first two seconds of every
  /// session.
  final GamepadService _gamepads = GamepadService();
  OnScreenControls _onScreenControls = OnScreenControls.auto;
  StreamSubscription<int>? _padMask;
  StreamSubscription<StKeyEvent>? _padKeys;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    // 2Hz: fast enough that the readout never looks stuck, slow enough to be
    // invisible next to the emulator's own 50Hz.
    _statusTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && widget.core.isRunning) setState(() {});
    });
    _startGamepads();
  }

  void _startGamepads() {
    _gamepads.start();
    _padMask = _gamepads.maskChanges.listen((mask) {
      if (!widget.core.isRunning) return;
      // Both ST ports. Games read port 1 and the mouse lives on port 0, but
      // a handful disagree and driving both costs nothing.
      widget.core.joystick(0, mask);
      widget.core.joystick(1, mask);
    });
    _padKeys = _gamepads.keyEvents.listen((event) {
      if (!widget.core.isRunning) return;
      widget.core.keyEvent(event.scancode, event.pressed);
    });
    // Rebuild when a pad appears or goes away, so the on-screen stick can
    // come and go with it.
    _gamepads.connected.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _padMask?.cancel();
    _padKeys?.cancel();
    _gamepads.connected.removeListener(_onControllerChanged);
    _gamepads.dispose();
    _statusTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final folder = await GamesFolder.resolve();
    var tos = await AppPrefs.tosPath();
    final machine = await AppPrefs.defaultMachine();
    final compliance = await AppPrefs.complianceMode();
    final onScreen = await AppPrefs.onScreenControls();
    final sidebarVisible = await AppPrefs.sidebarVisible();
    final volumes = await GamesFolder.candidates();
    SessionStore.useStateDir(Directory(widget.workDir));
    final resumePoints = await SessionStore.loadAll();
    final resume = await SessionStore.loadLast();
    final roms = TosStore.scan(widget.tosDir);

    // Pick a ROM rather than making the user do it, when there is one to pick
    // and nothing is set yet. Every title in the library is unlaunchable until
    // a TOS is chosen, so an app that CAN answer this and instead shows an
    // error on first launch is just being unhelpful.
    //
    // Also re-picked when the stored path no longer exists -- a ROM that was
    // deleted or moved would otherwise leave the app permanently unable to
    // boot with no indication of why.
    final storedIsUsable =
        tos != null && tos.isNotEmpty && File(tos).existsSync();
    if (!storedIsUsable) {
      final best = TosStore.bestFor(roms, machine);
      if (best != null) {
        tos = best.path;
        await AppPrefs.setTosPath(tos);
      } else {
        tos = null;
      }
    }

    if (!mounted) return;
    setState(() {
      _gamesFolder = folder;
      _roms = roms;
      _config = _config.copyWith(tosPath: tos ?? '', machine: machine);
      _complianceMode = compliance;
      _onScreenControls = onScreen;
      _sidebarHidden = !sidebarVisible;
      _volumeChoices = volumes;
      _resumePoints = resumePoints;
      _resumePoint = resume;
    });
    await _rescan();
  }

  Future<void> _rescan() async {
    setState(() => _scanning = true);

    // Compliance mode does not scan the user's library at all -- not "scans
    // it and hides the results". That distinction is the whole point of the
    // mode, so it is enforced here rather than in the widget that draws the
    // list.
    if (_complianceMode) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _unreadable = const [];
        _scanning = false;
      });
      return;
    }

    final result = await LibraryScanner.scan(_gamesFolder);
    if (!mounted) return;
    setState(() {
      _entries = result.entries;
      _unreadable = result.unreadable;
      _scanning = false;
    });
  }

  /// Launch a title, resuming it when there is a saved position.
  ///
  /// This is what makes "close the game" and "come back to it" symmetrical:
  /// tapping the card puts you where you were, not at the boot screen. Pass
  /// [fresh] to deliberately start from the beginning.
  Future<void> _launch(GameEntry entry, {bool fresh = false}) async {
    final saved = _resumePoints[entry.path];
    if (!fresh && saved != null) {
      await _resume(saved);
      return;
    }
    await _launchFresh(entry);
  }

  Future<void> _launchFresh(GameEntry entry) async {
    // Deliberately NOT stopping a running machine first: start() re-points a
    // live core at the new title and cold resets it. Stopping first would
    // reset the machine twice for no benefit -- and Hatari cannot be
    // initialised twice in one process anyway, which is why the core is
    // started once and hot-swapped from then on. See atarist_core_stop.
    final overrides = await AppPrefs.gameConfigs();
    var config = overrides[entry.path] ?? _config;

    switch (entry.kind) {
      case GameKind.floppy:
        config = config.copyWith(floppyA: entry.path, gemdosDir: '');
      case GameKind.floppySet:
        config = config.copyWith(
          floppyA: entry.disks.first,
          // Disk 2 goes straight into drive B. A two-drive ST owner would
          // have done exactly this, and it saves the first swap prompt.
          floppyB: entry.disks.length > 1 ? entry.disks[1] : '',
          gemdosDir: '',
        );
      case GameKind.gemdos:
        config = config.copyWith(gemdosDir: entry.path, floppyA: '');
      case GameKind.hardDisk:
        config = config.copyWith(acsiImage: entry.path, floppyA: '');
      case GameKind.archive:
        setState(() => _error =
            'Zip archives are not unpacked yet. Extract it into the games '
            'folder and rescan.');
        return;
    }

    // Protected formats need accurate FDC timing, and turning it on globally
    // would make every ordinary image take a period-authentic minute to load.
    if (entry.needsAccurateFloppy) {
      config = config.copyWith(accurateFloppy: true);
    }

    final result = widget.core.start(config);
    if (result != StResult.ok) {
      setState(() {
        _error = widget.core.lastError ?? StResult.describe(result);
        if (result == StResult.noTos) _tab = WorkbenchTab.machine;
      });
      return;
    }

    setState(() {
      _config = config;
      _running = entry;
      _error = null;
    });
    unawaited(_openSession());
  }

  /// Hands the session its own screen -- the family pattern shared with
  /// the other Retro-* front ends. Every way into a game funnels through
  /// here, so pausing and closing land back on the workbench in exactly
  /// one place; the engine-side work stays in [_pauseToResume] and
  /// [_exitSession], which the session screen calls before it pops.
  Future<void> _openSession() async {
    final running = _running;
    if (running == null || !mounted) return;
    await Navigator.of(context).push<SessionExit>(
      MaterialPageRoute<SessionExit>(
        fullscreenDialog: true,
        builder: (BuildContext context) => EmulatorSessionScreen(
          core: widget.core,
          entry: running,
          accurateFloppy: _config.accurateFloppy,
          onScreenControls: _onScreenControls,
          controllerConnected: _gamepads.connected,
          onInsertDisk: _insertDisk,
          onSaveAndExit: _pauseToResume,
          onClose: _exitSession,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Puts [path] in [drive] of the running machine.
  ///
  /// If the OTHER drive already holds that same image, it is ejected first.
  /// Multi-disk titles start with disk 1 in A and disk 2 in B, so swapping
  /// disk 2 into A -- which is what a single-drive loader asks for -- would
  /// otherwise leave one image mounted in both drives at once. Hatari allows
  /// it, and it is a good way to corrupt a writable image when both drives
  /// flush.
  void _insertDisk(int drive, String path) {
    final other = drive == 0 ? 1 : 0;
    if (widget.core.getFloppy(other) == path) {
      widget.core.setFloppy(other, null);
    }
    final result = widget.core.setFloppy(drive, path);
    if (result != StResult.ok) {
      setState(() => _error = widget.core.lastError ??
          'Could not insert that disk: ${StResult.describe(result)}');
    }
  }

  /// Write the current position for the running title.
  ///
  /// Used by BOTH the bookmark button and the exit button: closing a game
  /// should not throw away where you were, which is the whole point of
  /// having this at all. Returns false if nothing could be saved.
  ///
  /// The snapshot is written BEFORE the machine is stopped -- the save is
  /// serviced by the core's own thread at a VBL, so stopping first would
  /// leave nothing to come back to.
  Future<bool> _captureResumePoint() async {
    final entry = _running;
    if (entry == null || !widget.core.isRunning) return false;

    final statePath = SessionStore.statePathFor(entry.path);
    final result = widget.core.saveStateTo(statePath);
    if (result != StResult.ok) {
      setState(() => _error = widget.core.lastError ??
          'Could not save your position: ${StResult.describe(result)}');
      return false;
    }

    final point = ResumePoint(
      gamePath: entry.path,
      title: entry.title,
      config: _config,
      savedAt: DateTime.now(),
      statePath: statePath,
    );
    await SessionStore.save(point);
    if (!mounted) return true;
    setState(() {
      _resumePoints = {..._resumePoints, point.gamePath: point};
      _resumePoint = point;
    });
    return true;
  }

  /// Save and exit, engine side: capture the resume point and stop. The
  /// session screen navigates; this only changes what is running.
  Future<bool> _pauseToResume() async {
    if (!await _captureResumePoint()) return false;
    widget.core.stop();
    if (!mounted) return true;
    setState(() => _running = null);
    return true;
  }

  /// Put the user back exactly where they left off.
  Future<void> _resume([ResumePoint? which]) async {
    final point = which ?? _resumePoint;
    if (point == null) return;

    // The stored config, NOT the app's current defaults: a snapshot carries
    // RAM and hardware state that only make sense against the machine it was
    // taken on, so restoring into a different memory size or machine type
    // does not work.
    final result = widget.core.start(point.config);
    if (result != StResult.ok) {
      setState(() => _error = widget.core.lastError ??
          StResult.describe(result));
      return;
    }

    // start() is asynchronous -- the emulation thread is still inside
    // Main_Init when it returns -- and loadState needs a running core to
    // service the mailbox. Wait for it rather than racing.
    for (var i = 0; i < 100 && !widget.core.isRunning; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final loaded = widget.core.loadStateFrom(point.statePath);
    if (!mounted) return;
    if (loaded != StResult.ok) {
      // The machine is running, just not where they left it. Say so instead
      // of silently starting the title from the beginning as if nothing had
      // happened.
      setState(() => _error =
          'Could not restore the saved position -- the title has started '
          'from the beginning.');
    }

    setState(() {
      _config = point.config;
      _running = GameEntry(
        title: point.title,
        path: point.gamePath,
        kind: GameKind.floppy,
      );
    });
    unawaited(_openSession());
  }

  Future<void> _discardResume([String? gamePath]) async {
    final path = gamePath ?? _resumePoint?.gamePath;
    if (path == null) return;
    await SessionStore.clearFor(path);
    final remaining = await SessionStore.loadAll();
    final last = await SessionStore.loadLast();
    if (!mounted) return;
    setState(() {
      _resumePoints = remaining;
      _resumePoint = last;
      if (_resumePoint == null && _tab == WorkbenchTab.resume) {
        _tab = WorkbenchTab.games;
      }
    });
  }

  /// Leave the game.
  ///
  /// Saves your position on the way out rather than discarding it: there is
  /// no reason closing a title should be more destructive than pausing one,
  /// and a launcher that quietly loses twenty minutes of a protected original
  /// -- which took a minute just to load -- is doing the user a disservice.
  Future<void> _exitSession() async {
    await _captureResumePoint();
    widget.core.stop();
    if (!mounted) return;
    setState(() => _running = null);
  }

  /// True when the lifecycle handler paused the core, as opposed to the user
  /// pausing it from the control strip.
  ///
  /// Tracked as "did WE pause it" rather than "was it paused before": one
  /// backgrounding delivers several non-resumed events, and re-reading
  /// core.isPaused on the second one sees the pause we just applied and
  /// records it as the user's -- the resume then refuses to un-pause and the
  /// machine stays frozen for good.
  bool _pausedByLifecycle = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.core.isRunning) return;

    // Only a REAL backgrounding pauses the machine.
    //
    // The obvious version of this -- pause on anything that is not `resumed`
    // -- is wrong on desktop, and wrongly enough to look like a broken
    // emulator. On Linux `inactive` fires whenever the window merely loses
    // focus, so clicking on another window froze the ST mid-load; coming back
    // to a black screen reads as a title that failed to boot, not as a
    // deliberate pause. `hidden` and `paused` are the states that actually
    // mean "the user cannot see this".
    //
    // It still has to happen for the mobile targets: an emulation thread left
    // running in the background is a battery drain the user cannot see and
    // will not attribute to this app.
    final backgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;

    if (backgrounded) {
      if (!_pausedByLifecycle && !widget.core.isPaused) {
        widget.core.setPaused(true);
        _pausedByLifecycle = true;
      }
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      widget.core.setPaused(false);
      _pausedByLifecycle = false;
    }
    setState(() {});
  }

  Future<void> _setComplianceMode(bool enabled) async {
    await AppPrefs.setComplianceMode(enabled);
    setState(() => _complianceMode = enabled);
    await _rescan();
  }

  Future<void> _updateConfig(StMachineConfig next) async {
    setState(() => _config = next);
    await AppPrefs.setTosPath(
        next.tosPath == null || next.tosPath!.isEmpty ? null : next.tosPath);
    await AppPrefs.setDefaultMachine(next.machine);
  }

  List<SidebarDestination> get _destinations => [
        for (final tab in WorkbenchTab.values)
          // "Running" only appears while something is. A permanently visible
          // tab that is empty most of the time trains people to skip it, and
          // then they skip it on the one occasion it matters.
          if (_showsTab(tab))
            SidebarDestination(tab.title, icon: tab.icon, group: tab.group),
      ];

  /// Running only appears while something is; Resume only while there is
  /// something to go back to. A permanently visible tab that is empty most of
  /// the time trains people to skip it, and then they skip it on the one
  /// occasion it matters.
  bool _showsTab(WorkbenchTab tab) {
    if (tab == WorkbenchTab.running) return _running != null;
    if (tab == WorkbenchTab.resume) return _resumePoint != null;
    return true;
  }

  List<WorkbenchTab> get _visibleTabs => [
        for (final tab in WorkbenchTab.values)
          if (_showsTab(tab)) tab,
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs;
    var index = tabs.indexOf(_tab);
    if (index < 0) index = 0;

    // The session has its own screen now (EmulatorSessionScreen); the
    // workbench is only ever the launcher.
    return Column(
      children: [
        if (widget.usingStub) const _StubBanner(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RetroAtariStMetrics.rootPadding,
              RetroAtariStMetrics.rootPadding,
              RetroAtariStMetrics.rootPadding,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_sidebarHidden) ...[
                  Sidebar(
                    destinations: _destinations,
                    selectedIndex: index,
                    onSelected: (i) => setState(() => _tab = tabs[i]),
                    style: retroAtariStSidebarStyle,
                    pinLastGroupToBottom: true,
                    footer: _railFooter(),
                  ),
                  const SizedBox(width: RetroAtariStMetrics.contentLeftMargin),
                ],
                Expanded(child: _contentPanel()),
              ],
            ),
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  /// The strip beneath the window: the rail's show/hide toggle on the left
  /// and the last session's status. Outside both the rail and the content
  /// panel, deliberately -- the toggle is the only way back once the rail is
  /// hidden, so it cannot live inside the rail it controls. Sessions run on
  /// their own screen now, so this is launcher chrome only.
  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RetroAtariStMetrics.rootPadding,
        4,
        RetroAtariStMetrics.rootPadding,
        6,
      ),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            IconButton(
              onPressed: () async {
                final next = !_sidebarHidden;
                setState(() => _sidebarHidden = next);
                await AppPrefs.setSidebarVisible(!next);
              },
              icon: Icon(_sidebarHidden ? Icons.menu : Icons.menu_open,
                  size: 18),
              color: RetroAtariStColors.textMuted2,
              tooltip: _sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            // No section label here. The rail already names the selected
            // section a few pixels away, and when the rail is hidden the
            // panel's own content says what it is.
            Expanded(
              child: Text(
                widget.core.isRunning && _running != null
                    ? _sessionStatus()
                    : 'idle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RetroAtariStTextStyles.statusLine,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sessionStatus() {
    final core = widget.core;
    final parts = <String>[
      _running?.title ?? '',
      '${core.fps} fps',
      if (core.isPaused) 'paused',
      if (core.statusLine != null) core.statusLine!,
    ];
    return parts.where((p) => p.isNotEmpty).join('  |  ');
  }

  /// The way back into whatever the user stepped away from.
  Widget _resumePanel(ResumePoint point) {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RetroAtariStColors.cardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: RetroAtariStColors.accentAtariRed),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(point.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Paused ${point.ageDescription}  |  '
                '${point.config.machine.label}'
                '${point.config.memoryKb == null ? "" : ", ${point.config.memoryKb! ~/ 1024}MB"}',
                style: RetroAtariStTextStyles.statusLine,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _resume,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Resume'),
                    style: FilledButton.styleFrom(
                        backgroundColor: RetroAtariStColors.accentAtariRed),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _discardResume,
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your position is saved whenever you pause OR close a title, one '
          'snapshot per game -- so tapping any card marked RESUME puts you '
          'back where you were rather than at the boot screen. Long-press a '
          'card to start it from the beginning instead.\n\n'
          'Resuming restores the exact machine state -- memory, registers and '
          'the drive -- so a protected original does not have to load again '
          'from the beginning.\n\n'
          'It boots the machine this snapshot was taken on, not the current '
          'defaults: a snapshot carries RAM and hardware state that only make '
          'sense against the memory size and model it came from.',
          style: RetroAtariStTextStyles.statusLine,
        ),
      ],
    );
  }

  Widget _railFooter() {
    final core = widget.core;
    return Text(
      core.isRunning
          ? '${core.fps} fps${core.isPaused ? " (paused)" : ""}'
          : 'idle',
      style: RetroAtariStTextStyles.statusLine,
    );
  }

  Widget _contentPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RetroAtariStColors.panelFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RetroAtariStColors.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _errorBanner(_error!),
          Expanded(child: _tabContent()),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RetroAtariStColors.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: RetroAtariStColors.danger),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: Colors.white70,
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Widget _tabContent() {
    switch (_tab) {
      case WorkbenchTab.games:
        if (_scanning) {
          return const Center(child: CircularProgressIndicator());
        }
        return LibraryGrid(
          entries: _entries,
          unreadable: _unreadable,
          gamesFolderPath: _gamesFolder,
          resumablePaths: _resumePoints.keys.toSet(),
          onLaunch: _launch,
          onRescan: _rescan,
          onShowDetails: _showDetails,
        );

      case WorkbenchTab.running:
        final running = _running;
        if (running == null) {
          return const Center(
            child: Text('Nothing is running.',
                style: TextStyle(color: RetroAtariStColors.textMuted)),
          );
        }
        // The machine is alive on its own screen; this tab only exists as
        // a way back to it.
        return Center(
          child: TextButton.icon(
            onPressed: () => unawaited(_openSession()),
            icon: const Icon(Icons.play_arrow),
            label: Text('Return to ${running.title}'),
          ),
        );

      case WorkbenchTab.resume:
        final point = _resumePoint;
        if (point == null) {
          return const Center(
            child: Text('Nothing to resume.',
                style: TextStyle(color: RetroAtariStColors.textMuted)),
          );
        }
        return _resumePanel(point);

      case WorkbenchTab.machine:
        return MachineSettingsScreen(
          config: _config,
          onChanged: _updateConfig,
          availableRoms: _roms,
          tosDir: widget.tosDir,
        );

      case WorkbenchTab.media:
        return MediaSettingsScreen(
          config: _config,
          onChanged: (c) => setState(() => _config = c),
          runningCore: widget.core,
        );

      case WorkbenchTab.input:
        return InputSettingsScreen(
          config: _config,
          onChanged: (c) => setState(() => _config = c),
          gamepads: _gamepads,
          onScreenControls: _onScreenControls,
          onOnScreenControlsChanged: (mode) async {
            await AppPrefs.setOnScreenControls(mode);
            setState(() => _onScreenControls = mode);
          },
        );

      case WorkbenchTab.paths:
        return PathsSettingsScreen(
          gamesFolder: _gamesFolder,
          workDir: widget.workDir,
          tosDir: widget.tosDir,
          volumeChoices: _volumeChoices,
          onGamesFolderChanged: (dir) async {
            await AppPrefs.setGamesFolder(dir);
            setState(() => _gamesFolder = dir);
            await _rescan();
          },
        );

      case WorkbenchTab.compliance:
        return ComplianceScreen(
          complianceMode: _complianceMode,
          onComplianceModeChanged: _setComplianceMode,
          coreVersion: widget.core.coreVersion,
        );

      case WorkbenchTab.about:
        return AboutScreen(
          appBuild: widget.appBuild,
          coreVersion: widget.core.coreVersion,
          audioBackend: widget.core.audioBackend,
          usingStub: widget.usingStub,
          onRunSetupWizard: widget.onRunSetupWizard,
        );
    }
  }

  void _showDetails(GameEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RetroAtariStColors.rootBackground,
      isScrollControlled: true,
      builder: (context) => FutureBuilder<Map<String, StMachineConfig>>(
        future: AppPrefs.gameConfigs(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          var config = snapshot.data![entry.path] ?? _config;
          return StatefulBuilder(
            builder: (context, setSheetState) => SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.75,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The escape hatch for the fact that tapping a card now
                    // RESUMES. Without this there would be no way back to the
                    // start of a title once a position had been saved, which
                    // matters for a game you have finished or got stuck in.
                    if (_resumePoints.containsKey(entry.path))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Saved position from '
                                '${_resumePoints[entry.path]!.ageDescription}',
                                style: RetroAtariStTextStyles.statusLine,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _launch(entry, fresh: true);
                              },
                              child: const Text('Start from the beginning'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _discardResume(entry.path);
                              },
                              style: TextButton.styleFrom(
                                  foregroundColor:
                                      RetroAtariStColors.danger),
                              child: const Text('Discard'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: MachineSettingsScreen(
                        config: config,
                        titleName: entry.title,
                        availableRoms: _roms,
                        tosDir: widget.tosDir,
                        onChanged: (next) {
                          setSheetState(() => config = next);
                          AppPrefs.setGameConfig(entry.path, next);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Says plainly that no emulator is present.
///
/// Worth the screen space: without it, a stub session showing a synthetic
/// desktop looks like a broken emulator rather than an absent one, and that is
/// an expensive confusion to debug.
class _StubBanner extends StatelessWidget {
  const _StubBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: RetroAtariStColors.warning,
      padding: EdgeInsets.fromLTRB(
          12, 6 + MediaQuery.paddingOf(context).top, 12, 6),
      child: const Text(
        'Stub core: libatarist_core was not found, so nothing is being '
        'emulated. Build it with native/atarist_core/linux/build.sh '
        '(see docs/NATIVE_BUILD.md).',
        style: TextStyle(
            color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }
}
