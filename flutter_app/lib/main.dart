// App entry point: load the core, decide whether to run the wizard, hand off
// to the workbench.
//
// State management is setState plus a handful of statics, matching the sibling
// apps. That is a deliberate choice rather than an omission: the genuinely
// shared, long-lived state here is the emulator core, and a core is a
// process-wide native resource with a single owner, not something that
// benefits from a reactive graph.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'ffi/atarist_bindings.dart';
import 'ffi/atarist_core.dart';
import 'ffi/atarist_native_paths.dart';
import 'ffi/stub_atarist_core.dart';
import 'screens/setup_wizard_screen.dart';
import 'screens/workbench_screen.dart';
import 'services/app_prefs.dart';
import 'services/games_folder.dart';
import 'theme/retro_atarist_theme.dart';

void main() {
  runApp(const RetroAtariStApp());
}

class RetroAtariStApp extends StatefulWidget {
  const RetroAtariStApp({super.key});

  @override
  State<RetroAtariStApp> createState() => _RetroAtariStAppState();
}

class _RetroAtariStAppState extends State<RetroAtariStApp> {
  AtariStCore? _core;

  /// True when [_core] is the stub rather than the real native library, so
  /// the UI can say so instead of looking broken.
  bool _usingStub = false;

  bool? _setupCompleted;
  String? _appBuild;
  String _workDir = '';
  String _tosDir = '';
  String _gamesFolder = '';
  String? _tosPath;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final workDir = (await AtariStNativePaths.workDir()).path;
    final tosDir = (await AtariStNativePaths.tosDir()).path;
    final gamesFolder = await GamesFolder.resolve();
    final tosPath = await AppPrefs.tosPath();

    // The setup/compliance information is shown once per numbered build, not
    // once per installation. App upgrades preserve preferences, so a lone
    // boolean would stop testers and reviewers ever seeing revised first-run
    // information again.
    String? appBuild;
    try {
      final info = await PackageInfo.fromPlatform();
      appBuild = '${info.version}+${info.buildNumber}';
    } on Object catch (error) {
      // Package metadata can be unavailable under a test binding or on a new
      // platform integration. Fall back to the legacy boolean rather than
      // trapping that platform in the wizard on every launch.
      debugPrint('atarist: app build unavailable; setup is not build-keyed: '
          '$error');
    }
    final setupCompleted = appBuild == null
        ? await AppPrefs.isSetupCompleted()
        : await AppPrefs.setupCompletedForBuild(appBuild);

    AtariStCore core;
    bool usingStub;
    try {
      core = AtariStCoreBindings.load(
        libraryPath: AtariStNativePaths.coreLibraryPath,
      );
      usingStub = false;
    } on Object catch (e) {
      // Falling back rather than failing: the native core is a separate, slow
      // build that CI cannot produce, so an absent library is the normal
      // state during UI work. Catching broadly is intentional -- dlopen
      // failures surface as several different error types across platforms
      // and every one of them means the same thing.
      //
      // But it is reported, not swallowed: on a device the difference between
      // "no core was built" and "the core is there and dlopen refused it" is
      // invisible from the banner alone, and only this message distinguishes
      // them.
      debugPrint('atarist: falling back to the stub core. '
          'path=${AtariStNativePaths.coreLibraryPath} error=$e');
      core = StubAtariStCore();
      usingStub = true;
    }

    core.init(workDir, tosDir);

    if (!mounted) return;
    setState(() {
      _core = core;
      _usingStub = usingStub;
      _appBuild = appBuild;
      _setupCompleted = setupCompleted;
      _workDir = workDir;
      _tosDir = tosDir;
      _gamesFolder = gamesFolder;
      _tosPath = tosPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retro-AtariST',
      debugShowCheckedModeBanner: false,
      // No global fontFamily here on purpose: the sidebar measures its own
      // labels to size the rail, and a global override renders text wider
      // than the measurement, clipping labels ("Complian..."). Monospace is
      // applied per style via RetroAtariStTextStyles.
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: RetroAtariStColors.rootBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: RetroAtariStColors.accentAtariRed,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(body: _home()),
    );
  }

  Widget _home() {
    final core = _core;
    final setupCompleted = _setupCompleted;
    if (core == null || setupCompleted == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!setupCompleted) {
      return SetupWizardScreen(
        appBuild: _appBuild,
        gamesFolder: _gamesFolder,
        tosPath: _tosPath,
        onTosChosen: (path) async {
          await AppPrefs.setTosPath(path);
          setState(() => _tosPath = path);
        },
        onComplete: () async {
          await AppPrefs.markSetupCompleted(_appBuild);
          setState(() => _setupCompleted = true);
        },
      );
    }

    return WorkbenchScreen(
      core: core,
      usingStub: _usingStub,
      appBuild: _appBuild,
      workDir: _workDir,
      tosDir: _tosDir,
      onRunSetupWizard: () => setState(() => _setupCompleted = false),
    );
  }
}
