// Where the user's ST software lives, per platform.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_prefs.dart';

class GamesFolder {
  GamesFolder._();

  /// The configured folder, or a sensible per-platform default.
  ///
  /// On Android this is the app's own external files directory rather than a
  /// shared Documents folder: it needs no runtime permission, survives app
  /// updates, and is visible over USB -- which together are what let someone
  /// drop disk images in without the app asking for access to everything.
  static Future<String> resolve() async {
    final configured = await AppPrefs.gamesFolder();
    if (configured != null && configured.isNotEmpty) return configured;

    final Directory base;
    if (Platform.isAndroid) {
      final dirs = await getExternalStorageDirectories();
      base = (dirs != null && dirs.isNotEmpty)
          ? dirs.first
          : await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }

    final dir = Directory(p.join(base.path, 'AtariST'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }
}
