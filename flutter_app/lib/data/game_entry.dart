// One entry in the library.
import 'package:path/path.dart' as p;

/// What an entry actually IS on disk, which decides how it gets launched.
enum GameKind {
  /// A single floppy image: .st, .msa, .dim, .stx, .ipf.
  floppy('Floppy', 'FD'),

  /// A set of floppy images belonging to one title -- "Disk 1", "Disk 2".
  /// Launched with the first in drive A and the second in drive B, which is
  /// what a two-drive ST owner would have done.
  floppySet('Multi-disk', 'FD+'),

  /// A folder run through GEMDOS hard-disk emulation. How most modern ST
  /// software is distributed: no image, just files.
  gemdos('Folder', 'HD'),

  /// A raw ACSI or IDE hard disk image.
  hardDisk('Hard disk', 'IMG'),

  /// A zip that has not been looked inside yet.
  archive('Archive', 'ZIP');

  final String label;

  /// Drawn large in the card's cover slot while there is no box art. Kept to
  /// a few characters -- the slot is 120dp wide.
  final String badge;

  const GameKind(this.label, this.badge);
}

/// Extensions the scanner recognises as ST floppy images.
///
/// .stx and .ipf are protected-original formats (Pasti and SPS respectively).
/// They are listed because they are common in preservation sets, but they need
/// accurate FDC timing to work -- see StMachineConfig.accurateFloppy -- and
/// .ipf additionally needs Hatari to have been built with the capsimage
/// library. A title that will not load is worth showing with an explanation
/// rather than hiding.
const Set<String> kFloppyExtensions = {
  '.st', '.msa', '.dim', '.stx', '.ipf', '.raw', '.ctr', '.scp',
};

const Set<String> kHardDiskExtensions = {'.img', '.hda', '.vhd'};

class GameEntry {
  /// Display name. Derived from the filename with the disk-number suffix
  /// stripped, so "Dungeon Master (Disk 1).st" shows as "Dungeon Master".
  final String title;

  /// The thing to launch: an image file, or a directory for [GameKind.gemdos].
  final String path;

  final GameKind kind;

  /// For [GameKind.floppySet], every disk in order. Disk 1 goes in drive A;
  /// disk 2, if there is one, goes in drive B.
  final List<String> disks;

  const GameEntry({
    required this.title,
    required this.path,
    required this.kind,
    this.disks = const <String>[],
  });

  /// A second line for the card: the disk count, or the file extension.
  String? get subtitle {
    if (kind == GameKind.floppySet) return '${disks.length} disks';
    if (kind == GameKind.gemdos) return null;
    final ext = p.extension(path);
    return ext.isEmpty ? null : ext.substring(1).toUpperCase();
  }

  /// True for the formats that only work with cycle-accurate FDC timing.
  ///
  /// Used to default [StMachineConfig.accurateFloppy] per title rather than
  /// globally: turning it on for everything makes every ordinary .st image
  /// take a period-authentic minute to load, which is not what anyone wants
  /// from a launcher.
  bool get needsAccurateFloppy {
    final ext = p.extension(path).toLowerCase();
    return ext == '.stx' || ext == '.ipf' || ext == '.raw' || ext == '.ctr';
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'path': path,
        'kind': kind.name,
        if (disks.isNotEmpty) 'disks': disks,
      };

  factory GameEntry.fromJson(Map<String, dynamic> json) => GameEntry(
        title: json['title'] as String,
        path: json['path'] as String,
        kind: GameKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => GameKind.floppy,
        ),
        disks: ((json['disks'] as List<dynamic>?) ?? const <dynamic>[])
            .map((d) => d.toString())
            .toList(growable: false),
      );
}
