// Locating the native core library and the directories it may write to,
// per platform.
//
//   - Linux (dev): the .so is found by walking up to the repo root and
//     looking in native/atarist_core/linux/build/. Only works from a
//     checkout; packaging should ship it next to the executable and derive
//     the path from Platform.resolvedExecutable.
//   - Android: the .so ships in jniLibs/<abi>/ and is loaded by bare name, so
//     the path getter returns null on purpose.
//   - iOS: the core ships as a .framework inside the app bundle, opened by
//     explicit path.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AtariStNativePaths {
  AtariStNativePaths._();

  /// Walks up from the working directory (and from the script's own
  /// directory, for `flutter run`'s working-directory quirks) looking for a
  /// Retro-AtariST checkout root.
  static Directory? _findRepoRoot() {
    final candidates = <Directory>[
      Directory.current,
      Directory(p.dirname(Platform.script.toFilePath())),
    ];
    for (final start in candidates) {
      Directory dir = start;
      for (int i = 0; i < 8; i++) {
        if (Directory(p.join(dir.path, 'native', 'atarist_core')).existsSync()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  /// Absolute path to the core library, or null to fall back to bare-name
  /// loading (Android, where the OS loader resolves the .so from jniLibs).
  static String? get coreLibraryPath {
    if (Platform.isAndroid) return null;
    if (Platform.isIOS) return _iosFrameworkLibrary('libatarist_core');

    final root = _findRepoRoot();
    if (root == null) return null;

    final name = Platform.isMacOS
        ? 'libatarist_core.dylib'
        : Platform.isWindows
            ? 'atarist_core.dll'
            : 'libatarist_core.so';
    final path =
        p.join(root.path, 'native', 'atarist_core', 'linux', 'build', name);
    return File(path).existsSync() ? path : null;
  }

  /// Absolute path to a dylib shipped inside the iOS app bundle's Frameworks
  /// directory, which sits next to the executable.
  ///
  /// It ships as a .framework rather than a loose dylib because iOS validates
  /// every nested Mach-O in Frameworks/ as a code bundle and rejects the
  /// install otherwise (ApplicationVerificationFailed).
  static String? _iosFrameworkLibrary(String name) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final path = p.join(exeDir, 'Frameworks', '$name.framework', name);
    return File(path).existsSync() ? path : null;
  }

  /// Where the core may write: Hatari's own config, NVRAM and save states.
  ///
  /// Support rather than cache: a save state the user can come back to must
  /// not be something the system deletes when it wants space.
  static Future<Directory> workDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'core'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Where TOS ROM images live. The app never ships one -- TOS is
  /// copyrighted by Atari -- so this starts empty and the setup wizard asks
  /// the user to add theirs.
  static Future<Directory> tosDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'tos'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
