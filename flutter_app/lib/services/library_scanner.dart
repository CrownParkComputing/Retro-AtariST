// Turns a folder of ST software into library entries.
import 'dart:isolate';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/game_entry.dart';

class ScanResult {
  final List<GameEntry> entries;

  /// Paths that matched but could not be read. Reported in the library's
  /// status line because on Android this is what a scoped-storage permission
  /// problem looks like, and a quietly half-empty library is much harder to
  /// diagnose than a stated one.
  final List<String> unreadable;

  const ScanResult(this.entries, this.unreadable);
}

class LibraryScanner {
  LibraryScanner._();

  /// Matches the disk-number suffixes ST releases actually use, so the
  /// scanner can group the disks of one title into a single entry.
  ///
  /// Two families, both anchored at the end of the stem:
  ///
  ///   "(Disk 1 of 2)"  the TOSEC convention, which is what nearly every
  ///                    preservation set uses -- "Rainbow Islands
  ///                    (1990)(Ocean)(Disk 1 of 2).stx". The " of 2" is not
  ///                    optional decoration: without it the earlier pattern
  ///                    below fails to match and a two-disk game arrives as
  ///                    two unrelated entries, neither of which will get past
  ///                    its "insert disk 2" prompt.
  ///   "(Disk 1)"       and its relatives: "[disk 2]", "_d1", " Disk3".
  ///
  /// Anchored at the end so a title with a number in its NAME -- "Turrican 2",
  /// "R-Type II" -- is not mistaken for disk 2 of something and silently
  /// merged into the wrong entry. That failure is quiet and confusing, so the
  /// pattern errs towards not grouping.
  static final RegExp _diskSuffix = RegExp(
    r'[\s_\-]*[\(\[]?\s*(?:disk|disc|side)\s*(?:[0-9]+|[a-d])'
    r'(?:\s+of\s+[0-9]+)?\s*[\)\]]?$',
    caseSensitive: false,
  );

  /// The bare "(A)" / "(B)" form, as in "R-Type (A).STX".
  ///
  /// ROUND brackets only, deliberately. In square brackets a lone letter is
  /// TOSEC's alternate-dump marker -- "1943 (1987)(Probe Software)[a]" is a
  /// second dump of the SAME disk, not a second disk -- and stripping it would
  /// group two whole games into one bogus two-disk set.
  static final RegExp _diskLetterSuffix = RegExp(
    r'\s*\(([a-d])\)$',
    caseSensitive: false,
  );

  static String _titleOf(String filename) {
    final stem = p.basenameWithoutExtension(filename);
    var stripped = stem.replaceFirst(_diskSuffix, '').trim();
    if (stripped == stem) {
      stripped = stem.replaceFirst(_diskLetterSuffix, '').trim();
    }
    return stripped.isEmpty ? stem : stripped;
  }

  /// Sorts disk paths the way the disks are numbered, not the way the strings
  /// compare.
  ///
  /// Plain string order puts "Disk 10" before "Disk 2", which for a ten-disk
  /// title means drive A gets the wrong disk and nothing boots.
  static int _byDiskNumber(String a, String b) {
    int? numberIn(String path) {
      final match = RegExp(r'(?:disk|disc|side)\s*([0-9]+)', caseSensitive: false)
          .firstMatch(p.basenameWithoutExtension(path));
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final na = numberIn(a);
    final nb = numberIn(b);
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Runs on a background isolate: the walk crosses the games folder
  /// (often an SD card), and on the UI isolate every busy moment of the
  /// card was a dropped frame -- the stall class the Amiga live release
  /// taught us to move off the UI thread entirely.
  static Future<ScanResult> scan(String rootPath) =>
      Isolate.run(() => scanSync(rootPath));

  /// The walk itself, synchronous, for the isolate (and for tests).
  static Future<ScanResult> scanSync(String rootPath) async {
    final root = Directory(rootPath);
    if (!root.existsSync()) return const ScanResult([], []);

    final unreadable = <String>[];
    final floppiesByTitle = <String, List<String>>{};
    final entries = <GameEntry>[];

    late final List<FileSystemEntity> children;
    try {
      children = root.listSync(followLinks: false);
    } on FileSystemException {
      return ScanResult(const [], [rootPath]);
    }

    for (final child in children) {
      try {
        final name = p.basename(child.path);
        if (name.startsWith('.')) continue;

        if (child is Directory) {
          // A directory is a GEMDOS hard disk: the ST sees its contents as
          // C:. Not recursed into looking for floppy images -- a folder that
          // contains both a .st and a set of program files is ambiguous, and
          // treating it as a hard disk is the reading that works for both.
          entries.add(GameEntry(
            title: name,
            path: child.path,
            kind: GameKind.gemdos,
          ));
          continue;
        }

        if (child is! File) continue;
        final ext = p.extension(child.path).toLowerCase();

        if (kFloppyExtensions.contains(ext)) {
          floppiesByTitle
              .putIfAbsent(_titleOf(name), () => <String>[])
              .add(child.path);
        } else if (kHardDiskExtensions.contains(ext)) {
          entries.add(GameEntry(
            title: p.basenameWithoutExtension(name),
            path: child.path,
            kind: GameKind.hardDisk,
          ));
        } else if (ext == '.zip') {
          entries.add(GameEntry(
            title: p.basenameWithoutExtension(name),
            path: child.path,
            kind: GameKind.archive,
          ));
        }
      } on FileSystemException {
        unreadable.add(child.path);
      }
    }

    for (final entry in floppiesByTitle.entries) {
      final disks = entry.value..sort(_byDiskNumber);
      entries.add(GameEntry(
        title: entry.key,
        path: disks.first,
        kind: disks.length > 1 ? GameKind.floppySet : GameKind.floppy,
        disks: disks.length > 1 ? disks : const <String>[],
      ));
    }

    entries.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return ScanResult(entries, unreadable);
  }
}
