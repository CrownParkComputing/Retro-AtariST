// The "go back to what you were playing" record.
//
// Modelled on Retro-Amiga's Session marker, with one difference that follows
// from the architecture: the Amiga app runs its emulator in a separate process
// on Android, so its marker has to be a FILE both processes can see. Hatari
// runs in-process here, so the record is just a preference -- but it is still
// written to disk rather than held in memory, because the case worth surviving
// is the app being killed by the system, not the app closing tidily.
//
// The snapshot itself is a real Hatari machine snapshot in slot 0, written by
// the core's own thread. Slot 0 is reserved for resume; 1..9 are the user's.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../ffi/atarist_core.dart';

/// A title the user stepped away from, and everything needed to put them back.
class ResumePoint {
  /// Library path of the title, so the entry can be matched back to the grid.
  final String gamePath;

  /// Shown on the Resume panel.
  final String title;

  /// The exact machine it was running -- not the app's current defaults.
  ///
  /// Restoring a snapshot into a differently-configured machine does not
  /// work: Hatari's snapshot carries RAM contents and hardware state that
  /// only make sense against the memory size and machine type they were taken
  /// on. Storing the config alongside is what makes resume reliable after the
  /// user has changed a setting in between.
  final StMachineConfig config;

  /// When it was taken, for "paused 20 minutes ago".
  final DateTime savedAt;

  /// The snapshot file for THIS title.
  final String statePath;

  const ResumePoint({
    required this.gamePath,
    required this.title,
    required this.config,
    required this.savedAt,
    required this.statePath,
  });

  Map<String, dynamic> toJson() => {
        'gamePath': gamePath,
        'title': title,
        'config': config.toJson(),
        'savedAt': savedAt.toIso8601String(),
        'statePath': statePath,
      };

  static ResumePoint? fromJson(Map<String, dynamic> json) {
    final savedAt = DateTime.tryParse((json['savedAt'] ?? '') as String);
    if (savedAt == null) return null;
    final statePath = (json['statePath'] ?? '') as String;
    if (statePath.isEmpty) return null;
    return ResumePoint(
      gamePath: (json['gamePath'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      config: StMachineConfig.fromJson(
          (json['config'] as Map<String, dynamic>?) ?? const {}),
      savedAt: savedAt,
      statePath: statePath,
    );
  }

  String get ageDescription {
    final age = DateTime.now().difference(savedAt);
    if (age.inMinutes < 1) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes} minutes ago';
    if (age.inHours < 24) return '${age.inHours} hours ago';
    return '${age.inDays} days ago';
  }
}

class SessionStore {
  SessionStore._();

  /// One record per title, keyed by its library path.
  static const String _key = 'resume_points';

  /// Which title was last put down, so the Resume tab has something to show
  /// without the user hunting for it in the grid.
  static const String _lastKey = 'resume_last';

  /// Slot reserved for the automatic resume point in the OLD slot-based API.
  /// Kept only so a state written by an earlier build is not silently
  /// mistaken for a user slot.
  static const int resumeSlot = 0;

  /// The first slot the user can write to.
  static const int firstUserSlot = 1;

  static Directory? _stateDir;

  /// Where per-title snapshots live. Set once at startup.
  static void useStateDir(Directory dir) => _stateDir = dir;

  /// The snapshot file for [gamePath].
  ///
  /// Named from a hash of the path, not from the title. Titles are not unique
  /// (five dumps of 1943 all claim to be "1943"), they contain characters no
  /// filesystem agrees about -- brackets, colons, slashes in "Disk 1 of 2" --
  /// and they change when the scanner's naming improves, which would orphan
  /// every saved position. The path is stable and the hash is always a legal
  /// filename.
  static String statePathFor(String gamePath) {
    final dir = _stateDir?.path ?? '';
    final digest = sha1.convert(gamePath.codeUnits).toString().substring(0, 16);
    return p.join(dir, 'titles', '$digest.sav');
  }

  static Future<Map<String, ResumePoint>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, ResumePoint>{};
      decoded.forEach((key, value) {
        final point = ResumePoint.fromJson(value as Map<String, dynamic>);
        // Drop records whose snapshot has been deleted from under us --
        // offering a resume that cannot happen is worse than not offering one.
        if (point != null && File(point.statePath).existsSync()) {
          out[key] = point;
        }
      });
      return out;
    } on FormatException {
      // A corrupted blob loses saved positions, which is annoying. A
      // corrupted blob that throws on every launch loses the whole app.
      return {};
    }
  }

  /// The most recently put-down title, if its snapshot is still there.
  static Future<ResumePoint?> loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastKey);
    if (last == null || last.isEmpty) return null;
    return (await loadAll())[last];
  }

  static Future<ResumePoint?> loadFor(String gamePath) async =>
      (await loadAll())[gamePath];

  static Future<void> save(ResumePoint point) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    all[point.gamePath] = point;
    await prefs.setString(
        _key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_lastKey, point.gamePath);
  }

  static Future<void> clearFor(String gamePath) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    final removed = all.remove(gamePath);
    if (removed != null) {
      try {
        final file = File(removed.statePath);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // The record is gone either way; a stale file costs a few hundred KB.
      }
    }
    await prefs.setString(
        _key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
    if (prefs.getString(_lastKey) == gamePath) await prefs.remove(_lastKey);
  }
}
