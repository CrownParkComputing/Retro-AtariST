// Scanner tests against a real temp directory. No emulator, no device.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:retro_atarist/data/game_entry.dart';
import 'package:retro_atarist/services/library_scanner.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('atarist_scan');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  void touch(String name) {
    final file = File(p.join(root.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');
  }

  test('groups the disks of one title into a single entry', () async {
    touch('Dungeon Master (Disk 1).st');
    touch('Dungeon Master (Disk 2).st');

    final result = await LibraryScanner.scan(root.path);
    expect(result.entries, hasLength(1));

    final entry = result.entries.single;
    expect(entry.title, 'Dungeon Master');
    expect(entry.kind, GameKind.floppySet);
    expect(entry.disks, hasLength(2));
    // Disk 1 must be the one that goes in drive A.
    expect(p.basename(entry.path), contains('Disk 1'));
  });

  test('a title whose NAME ends in a number is not mistaken for a disk',
      () async {
    // The failure this guards is quiet and confusing: "Turrican 2" merged
    // into "Turrican" as its second disk, so one of them vanishes from the
    // library and the other will not boot.
    touch('Turrican.st');
    touch('Turrican 2.st');

    final result = await LibraryScanner.scan(root.path);
    expect(result.entries, hasLength(2));
    expect(
      result.entries.map((e) => e.title).toSet(),
      {'Turrican', 'Turrican 2'},
    );
    for (final entry in result.entries) {
      expect(entry.kind, GameKind.floppy);
    }
  });

  test('recognises the formats the ST actually uses', () async {
    touch('Xenon 2.msa');
    touch('Vroom.stx');
    touch('Rick Dangerous.dim');
    touch('Speedball.ipf');

    final result = await LibraryScanner.scan(root.path);
    expect(result.entries, hasLength(4));
    expect(result.entries.every((e) => e.kind == GameKind.floppy), isTrue);

    // The protected formats must ask for accurate FDC timing; the plain ones
    // must not, or every ordinary image takes a period-authentic minute.
    final byTitle = {for (final e in result.entries) e.title: e};
    expect(byTitle['Vroom']!.needsAccurateFloppy, isTrue);
    expect(byTitle['Speedball']!.needsAccurateFloppy, isTrue);
    expect(byTitle['Xenon 2']!.needsAccurateFloppy, isFalse);
    expect(byTitle['Rick Dangerous']!.needsAccurateFloppy, isFalse);
  });

  test('a subdirectory becomes a GEMDOS hard disk', () async {
    Directory(p.join(root.path, 'Sundown Demo')).createSync();

    final result = await LibraryScanner.scan(root.path);
    expect(result.entries, hasLength(1));
    expect(result.entries.single.kind, GameKind.gemdos);
    expect(result.entries.single.title, 'Sundown Demo');
  });

  test('ignores dotfiles and unrelated files', () async {
    touch('.DS_Store');
    touch('readme.txt');
    touch('Real Game.st');

    final result = await LibraryScanner.scan(root.path);
    expect(result.entries.map((e) => e.title), ['Real Game']);
  });

  test('a missing folder is empty, not an error', () async {
    final result =
        await LibraryScanner.scan(p.join(root.path, 'does-not-exist'));
    expect(result.entries, isEmpty);
    expect(result.unreadable, isEmpty);
  });

  test('entries come back sorted case-insensitively', () async {
    touch('zeta.st');
    touch('Alpha.st');
    touch('beta.st');

    final result = await LibraryScanner.scan(root.path);
    expect(result.entries.map((e) => e.title), ['Alpha', 'beta', 'zeta']);
  });

  group('real-world names from the imported library', () {
    test('groups TOSEC "(Disk 1 of 2)" pairs', () async {
      touch('Rainbow Islands (1990)(Ocean)(Disk 1 of 2).stx');
      touch('Rainbow Islands (1990)(Ocean)(Disk 2 of 2).stx');
      touch('Super Hang-On (1988)(Sega)(Disk 1 of 2).stx');
      touch('Super Hang-On (1988)(Sega)(Disk 2 of 2).stx');

      final result = await LibraryScanner.scan(root.path);
      expect(result.entries, hasLength(2));
      for (final entry in result.entries) {
        expect(entry.kind, GameKind.floppySet);
        expect(entry.disks, hasLength(2));
        expect(p.basename(entry.path), contains('Disk 1'));
      }
    });

    test('groups the bare "(A)" / "(B)" form', () async {
      touch('R-Type (A).STX');
      touch('R-Type (B).STX');

      final result = await LibraryScanner.scan(root.path);
      expect(result.entries, hasLength(1));
      expect(result.entries.single.title, 'R-Type');
      expect(result.entries.single.disks, hasLength(2));
    });

    test('"R-Type II" is its own game, not disk 2 of "R-Type"', () async {
      touch('R-Type (A).STX');
      touch('R-Type (B).STX');
      touch('R-Type II (1989)(Irem)(Disk 1 of 2).stx');
      touch('R-Type II (1989)(Irem)(Disk 2 of 2).stx');

      final result = await LibraryScanner.scan(root.path);
      expect(result.entries, hasLength(2));
      expect(
        result.entries.map((e) => e.title).toSet(),
        {'R-Type', 'R-Type II (1989)(Irem)'},
      );
    });

    test('[a] alt-dump markers do NOT group two games into a disk set', () {
      // The real trap: "[a]" in SQUARE brackets is TOSEC for "alternate dump
      // of the same disk". Treating it as a disk letter would fuse two whole
      // games of 1943 into one bogus two-disk entry.
      touch('1943 (1987)(Probe Software)[cr Bladerunners].st');
      touch('1943 (1987)(Probe Software)[cr Bladerunners][a].st');

      return LibraryScanner.scan(root.path).then((result) {
        expect(result.entries, hasLength(2));
        for (final entry in result.entries) {
          expect(entry.kind, GameKind.floppy);
        }
      });
    });

    test('disk 10 sorts after disk 2, so drive A gets disk 1', () async {
      for (var i = 1; i <= 11; i++) {
        touch('Epic (1992)(Ocean)(Disk $i of 11).st');
      }
      final result = await LibraryScanner.scan(root.path);
      expect(result.entries, hasLength(1));
      final disks = result.entries.single.disks;
      expect(p.basename(disks.first), contains('Disk 1 of'));
      expect(p.basename(disks[1]), contains('Disk 2 of'));
      expect(p.basename(disks.last), contains('Disk 11 of'));
    });
  });
}
