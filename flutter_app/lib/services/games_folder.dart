// Where the user's ST software lives, per platform.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_prefs.dart';

class GamesFolder {
  GamesFolder._();

  /// The configured folder, or a sensible per-platform default.
  ///
  /// On Android this is an app-specific external directory: it needs no
  /// runtime permission, survives app updates, and is visible over USB --
  /// which together are what let someone drop disk images in without the app
  /// asking for access to everything.
  ///
  /// **The removable card is preferred when there is one.** getExternal-
  /// StorageDirectories returns one directory per volume, primary (built-in)
  /// first, and taking `.first` is the obvious choice that is wrong for this
  /// class of device: the Retroid this was tested on has 2.4GB free of its
  /// built-in storage and 257GB free on its card, and an ST collection is
  /// hundreds of files. A launcher that defaults to the volume that cannot
  /// hold the library is not much use.
  ///
  /// Paths settings can still override it either way.
  static Future<String> resolve() async {
    final configured = await AppPrefs.gamesFolder();
    if (configured != null && configured.isNotEmpty) return configured;

    final Directory base;
    if (Platform.isAndroid) {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null && dirs.isNotEmpty) {
        // Last, not first: secondary volumes come after the primary one.
        base = dirs.last;
      } else {
        base = await getApplicationDocumentsDirectory();
      }
    } else {
      base = await getApplicationDocumentsDirectory();
    }

    final dir = Directory(p.join(base.path, 'AtariST'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Every candidate games folder, for the Paths screen to offer.
  ///
  /// Shown as a choice rather than left to a file picker because on Android
  /// an app-specific directory on a removable card is genuinely hard to reach
  /// through the system picker, and it is exactly where the library wants to
  /// live.
  static Future<List<String>> candidates() async {
    if (!Platform.isAndroid) return const [];
    final dirs = await getExternalStorageDirectories();
    if (dirs == null) return const [];
    return dirs
        .map((d) => p.join(d.path, 'AtariST'))
        .toList(growable: false);
  }
}
