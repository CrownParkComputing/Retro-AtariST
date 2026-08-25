// Finding and identifying the TOS ROMs the user has supplied.
//
// Filenames are not trusted for any of this. ROM dumps arrive named
// "tos.img", "Tos102.img", "TOS v1.62 (1990)(Atari Corp)(STE)(US)[STE TOS,
// Rev 2].img" and worse, and the same file gets renamed on the way between
// machines. The version is in the ROM itself, so it is read from there.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../ffi/atarist_core.dart';

/// One TOS ROM found on disk, identified by its own header.
class TosRom {
  final String path;

  /// BCD-ish version word at offset 2, e.g. 0x0102 for TOS 1.02.
  final int versionWord;

  final int sizeBytes;

  const TosRom({
    required this.path,
    required this.versionWord,
    required this.sizeBytes,
  });

  /// "1.02", "2.06", "4.04".
  String get version {
    final major = (versionWord >> 8) & 0xFF;
    final minor = versionWord & 0xFF;
    return '$major.${minor.toRadixString(16).padLeft(2, '0')}';
  }

  /// EmuTOS is an open reimplementation of TOS. It reports itself as 2.06 in
  /// the version word but is 512K or larger, which is the only thing that
  /// distinguishes it from a real 2.06 ROM (256K) without reading strings out
  /// of the image.
  bool get isEmuTos => versionWord == 0x0206 && sizeBytes >= 512 * 1024;

  String get label {
    if (isEmuTos) return 'EmuTOS ${_sizeLabel()}';
    return 'TOS $version (${_sizeLabel()})';
  }

  String _sizeLabel() => '${sizeBytes ~/ 1024}K';

  /// TOS major version, e.g. 1 for 1.02.
  int get major => (versionWord >> 8) & 0xFF;

  /// TOS minor version as its printed digits, e.g. 62 for 1.62 -- the version
  /// word stores it in hex nibbles, so 0x62 means "62", not 98.
  int get minor => int.parse((versionWord & 0xFF).toRadixString(16));

  /// The machines this ROM will actually boot.
  ///
  /// Getting this wrong is not a subtle failure: a mismatched ROM either
  /// halts the CPU with a double bus fault -- which the app reports as
  /// "the emulated CPU halted" -- or comes up in the wrong screen mode and
  /// sits there, which reads as the game failing to launch.
  Set<StMachine> get suitableFor {
    if (isEmuTos) {
      // EmuTOS runs on everything, which is why it is the safe last resort.
      return StMachine.values.toSet();
    }
    switch (major) {
      case 1:
        // 1.00-1.04 are the ST/Mega ST ROMs; 1.06 and 1.62 are STE-only and
        // will not boot a plain ST.
        return minor < 6
            ? {StMachine.st, StMachine.megaSt}
            : {StMachine.ste};
      case 2:
        return {
          StMachine.st,
          StMachine.megaSt,
          StMachine.ste,
          StMachine.megaSte,
        };
      case 3:
        return {StMachine.tt};
      case 4:
        return {StMachine.falcon};
      default:
        return const {};
    }
  }

  /// How *native* this ROM is to [machine]: lower is better, and anything
  /// above [unusableRank] means it will not boot at all.
  ///
  /// This exists because "newest" is the wrong answer and picking it broke
  /// exactly this way: with TOS 1.02 and TOS 2.06 both installed, a
  /// newest-first choice put 2.06 on a plain ST, where it comes up in mono
  /// and sits at the memory test forever. The machine looked like it had
  /// booted, so it read as "the game will not launch" rather than as the
  /// wrong ROM. The right answer is the ROM the machine actually shipped
  /// with.
  static const int unusableRank = 100;

  int rankFor(StMachine machine) {
    if (!suitableFor.contains(machine)) return unusableRank;
    if (isEmuTos) return 50; // works everywhere, native to nothing

    switch (machine) {
      case StMachine.st:
      case StMachine.megaSt:
        // 1.04 is the last and best ST ROM; older ones still shipped on the
        // machine, so they rank just behind it. 2.06 boots but is a later
        // machine's ROM.
        if (major == 1) return 10 - minor.clamp(0, 4);
        return 30;
      case StMachine.ste:
        // 1.62 is the STE's own final ROM.
        if (major == 1) return 10 - (minor - 6).clamp(0, 4);
        return 30;
      case StMachine.megaSte:
        if (major == 2) return 6;
        return 30;
      case StMachine.tt:
        return major == 3 ? 6 : 30;
      case StMachine.falcon:
        return major == 4 ? 6 : 30;
    }
  }

  String get fileName => p.basename(path);
}

class TosStore {
  TosStore._();

  /// TOS ROM images start with BRA.S over the header (0x602E). Every real
  /// dump from TOS 1.00 to 4.04 has it, which makes it a far better test than
  /// any file extension.
  static const int _braShort = 0x602E;

  /// The sizes Atari actually shipped, plus EmuTOS's 512K and 1M builds.
  /// A file that passes the header check but is 512788 bytes -- which is
  /// exactly what one image in the wild turned out to be -- is padded or
  /// truncated and will not boot.
  static const Set<int> _validSizes = {
    192 * 1024,
    256 * 1024,
    512 * 1024,
    1024 * 1024,
  };

  /// Reads and identifies one candidate, or null if it is not a TOS ROM.
  static TosRom? identify(File file) {
    if (!file.existsSync()) return null;

    final int size;
    try {
      size = file.lengthSync();
    } on FileSystemException {
      return null;
    }
    if (!_validSizes.contains(size)) return null;

    final Uint8List head;
    try {
      final handle = file.openSync();
      try {
        head = handle.readSync(4);
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return null;
    }
    if (head.length < 4) return null;

    final magic = (head[0] << 8) | head[1];
    if (magic != _braShort) return null;

    return TosRom(
      path: file.path,
      versionWord: (head[2] << 8) | head[3],
      sizeBytes: size,
    );
  }

  /// Every TOS ROM in [dir], newest version first.
  static List<TosRom> scan(String dir) {
    final directory = Directory(dir);
    if (!directory.existsSync()) return const [];

    final roms = <TosRom>[];
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final rom = identify(entity);
      if (rom != null) roms.add(rom);
    }

    roms.sort((a, b) {
      // EmuTOS last: it boots anything, but it is a reimplementation and a
      // real ROM is the better choice when one is present.
      if (a.isEmuTos != b.isEmuTos) return a.isEmuTos ? 1 : -1;
      return b.versionWord.compareTo(a.versionWord);
    });
    return roms;
  }

  /// The ROM to use for [machine], or null if none of [roms] will boot it.
  ///
  /// Ranked by how native each ROM is to the machine (see [TosRom.rankFor]),
  /// NOT by version. Returning the newest ROM is what put TOS 2.06 on a plain
  /// ST and left it sitting at the memory test.
  static TosRom? bestFor(List<TosRom> roms, StMachine machine) {
    TosRom? best;
    var bestRank = TosRom.unusableRank;
    for (final rom in roms) {
      final rank = rom.rankFor(machine);
      if (rank < bestRank) {
        bestRank = rank;
        best = rom;
      }
    }
    return best;
  }
}
