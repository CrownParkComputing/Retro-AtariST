// Small persisted settings. Deliberately a thin wrapper over
// SharedPreferences rather than a settings framework: there are a dozen keys,
// they are independent, and the app has no reactive graph to feed.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../ffi/atarist_core.dart';

/// When to draw the on-screen joystick over the emulator picture.
enum OnScreenControls {
  auto('Automatic',
      'Hidden while a controller is connected, shown when there is none.'),
  always('Always shown', 'Even with a controller connected.'),
  never('Never shown',
      'For a machine that always has a controller, or a keyboard-only game.');

  final String label;
  final String blurb;
  const OnScreenControls(this.label, this.blurb);
}

class AppPrefs {
  AppPrefs._();

  static const _kSetupCompletedBuild = 'setup_completed_build';
  static const _kSetupCompleted = 'setup_completed';
  static const _kGamesFolder = 'games_folder';
  static const _kTosPath = 'tos_path';
  static const _kDefaultMachine = 'default_machine';
  static const _kComplianceMode = 'compliance_mode';
  static const _kSidebarVisible = 'sidebar_visible';
  static const _kOnScreenControls = 'on_screen_controls';
  static const _kScreenFill = 'screen_fill';

  /// Whether the setup wizard has been completed FOR THIS BUILD.
  ///
  /// Keyed by build, not by installation: app upgrades preserve
  /// SharedPreferences, so a lone boolean would stop testers and store
  /// reviewers ever seeing revised first-run information again.
  static Future<bool> setupCompletedForBuild(String build) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSetupCompletedBuild) == build;
  }

  static Future<void> markSetupCompleted(String? build) async {
    final prefs = await SharedPreferences.getInstance();
    if (build != null) await prefs.setString(_kSetupCompletedBuild, build);
    await prefs.setBool(_kSetupCompleted, true);
  }

  /// Legacy fallback for platforms where package metadata is unavailable.
  static Future<bool> isSetupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSetupCompleted) ?? false;
  }

  static Future<String?> gamesFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGamesFolder);
  }

  static Future<void> setGamesFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGamesFolder, path);
  }

  static Future<String?> tosPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTosPath);
  }

  static Future<void> setTosPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_kTosPath);
    } else {
      await prefs.setString(_kTosPath, path);
    }
  }

  static Future<StMachine> defaultMachine() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kDefaultMachine);
    return StMachine.values.firstWhere(
      (m) => m.name == name,
      // The plain ST, not the STE: an STE runs almost every ST title, but a
      // handful of 1986-88 games detect the extra hardware and misbehave,
      // and a default that is wrong for a few titles in ways that look like
      // emulator bugs is worse than one that is merely less capable.
      orElse: () => StMachine.st,
    );
  }

  static Future<void> setDefaultMachine(StMachine machine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultMachine, machine.name);
  }

  static Future<OnScreenControls> onScreenControls() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kOnScreenControls);
    return OnScreenControls.values.firstWhere(
      (m) => m.name == name,
      orElse: () => OnScreenControls.auto,
    );
  }

  static Future<void> setOnScreenControls(OnScreenControls mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOnScreenControls, mode.name);
  }

  /// Stretch the ST picture to fill the screen instead of keeping its 4:3
  /// shape. Off by default: 4:3 is what the hardware produced.
  static Future<bool> screenFill() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kScreenFill) ?? false;
  }

  static Future<void> setScreenFill(bool fill) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kScreenFill, fill);
  }

  /// Compliance mode: only the bundled demo is offered and the user's own
  /// library is not scanned at all. Every app in this family has one.
  static Future<bool> complianceMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kComplianceMode) ?? false;
  }

  static Future<void> setComplianceMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kComplianceMode, enabled);
  }

  static Future<bool> sidebarVisible() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSidebarVisible) ?? true;
  }

  static Future<void> setSidebarVisible(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSidebarVisible, visible);
  }

  /// Per-title machine overrides, keyed by the title's path.
  ///
  /// Stored as one JSON blob rather than a key per title: the whole map is
  /// read on every launch and written on every edit, and a hundred separate
  /// keys would be a hundred platform round trips for no benefit.
  static Future<Map<String, StMachineConfig>> gameConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('game_configs');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(
          key, StMachineConfig.fromJson(value as Map<String, dynamic>)));
    } on FormatException {
      // A corrupted blob loses per-title overrides, which is annoying; a
      // corrupted blob that throws on every launch loses the whole app.
      return {};
    }
  }

  static Future<void> setGameConfig(String path, StMachineConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await gameConfigs();
    all[path] = config;
    await prefs.setString('game_configs',
        jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
  }
}
