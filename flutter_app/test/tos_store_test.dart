// TOS identification, tested against synthesised ROM headers.
//
// No real ROM is committed or needed: the identification reads four bytes and
// a file length, so a file with the right header and the right size exercises
// exactly the code path a real dump does.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:retro_atarist/ffi/atarist_core.dart';
import 'package:retro_atarist/services/tos_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('atarist_tos');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// Writes a file that looks exactly like a TOS ROM to the identifier:
  /// BRA.S (0x602E), the version word, padded to [sizeKb].
  File writeRom(String name, int versionWord, int sizeKb) {
    final bytes = Uint8List(sizeKb * 1024);
    bytes[0] = 0x60;
    bytes[1] = 0x2E;
    bytes[2] = (versionWord >> 8) & 0xFF;
    bytes[3] = versionWord & 0xFF;
    final file = File(p.join(root.path, name))..writeAsBytesSync(bytes);
    return file;
  }

  test('identifies a ROM by its header, not its filename', () {
    // Deliberately a misleading name: dumps get renamed constantly, and the
    // version is in the ROM itself.
    final rom = TosStore.identify(writeRom('totally-not-tos.bin', 0x0102, 192));
    expect(rom, isNotNull);
    expect(rom!.version, '1.02');
    expect(rom.isEmuTos, isFalse);
  });

  test('rejects a file that is not a TOS ROM', () {
    final junk = File(p.join(root.path, 'tos.img'))
      ..writeAsBytesSync(Uint8List(192 * 1024));
    expect(TosStore.identify(junk), isNull);
  });

  test('rejects a correct header at a wrong size', () {
    // A real image in the wild turned out to be 512788 bytes -- right header,
    // padded length. It passes every filename check and will not boot.
    final bytes = Uint8List(512788);
    bytes[0] = 0x60;
    bytes[1] = 0x2E;
    bytes[2] = 0x02;
    bytes[3] = 0x06;
    final file = File(p.join(root.path, 'tos492.img'))
      ..writeAsBytesSync(bytes);
    expect(TosStore.identify(file), isNull);
  });

  test('tells EmuTOS apart from a real 2.06 by size alone', () {
    final real = TosStore.identify(writeRom('tos206.img', 0x0206, 256))!;
    final emu = TosStore.identify(writeRom('etos512us.img', 0x0206, 512))!;
    expect(real.isEmuTos, isFalse);
    expect(emu.isEmuTos, isTrue);
    expect(emu.label, contains('EmuTOS'));
    // EmuTOS boots anything, which is what makes it the safe fallback.
    expect(emu.suitableFor, containsAll(StMachine.values));
  });

  test('a TOS 1.02 ROM is not offered for an STE', () {
    // The failure this prevents is a double bus fault on boot, which the app
    // reports as "the emulated CPU halted" -- indistinguishable from an
    // emulator bug unless you already know.
    final rom = TosStore.identify(writeRom('tos102.img', 0x0102, 192))!;
    expect(rom.suitableFor, contains(StMachine.st));
    expect(rom.suitableFor, isNot(contains(StMachine.ste)));
  });

  test('STE-only 1.62 is not offered for a plain ST', () {
    final rom = TosStore.identify(writeRom('tos162.img', 0x0162, 256))!;
    expect(rom.suitableFor, {StMachine.ste});
    expect(rom.rankFor(StMachine.st), TosRom.unusableRank);
  });

  test('minor version is read as printed digits, not hex', () {
    // 0x62 is "62" on the badge, not 98. Getting this wrong put 1.62 in the
    // 1.00-1.04 ST band.
    final rom = TosStore.identify(writeRom('tos162.img', 0x0162, 256))!;
    expect(rom.version, '1.62');
    expect(rom.minor, 62);
  });

  test('a plain ST gets TOS 1.0x, NOT the newer 2.06', () {
    // The regression this locks down: picking "newest" put TOS 2.06 on a
    // plain ST, where it comes up in mono and sits at the memory test
    // forever. The machine looks booted, so it reads as "the game will not
    // launch" rather than as the wrong ROM.
    final tos102 = TosStore.identify(writeRom('a.img', 0x0102, 192))!;
    final tos206 = TosStore.identify(writeRom('b.img', 0x0206, 256))!;

    expect(TosStore.bestFor([tos206, tos102], StMachine.st), tos102);
    expect(TosStore.bestFor([tos102, tos206], StMachine.st), tos102);
    // But 2.06 is still the right answer for the machine that shipped it.
    expect(TosStore.bestFor([tos102, tos206], StMachine.megaSte), tos206);
  });

  test('an STE gets 1.62 over 2.06, and over ST-only 1.02', () {
    final tos102 = TosStore.identify(writeRom('a.img', 0x0102, 192))!;
    final tos162 = TosStore.identify(writeRom('b.img', 0x0162, 256))!;
    final tos206 = TosStore.identify(writeRom('c.img', 0x0206, 256))!;
    expect(
      TosStore.bestFor([tos102, tos206, tos162], StMachine.ste),
      tos162,
    );
  });

  test('1.04 beats 1.00 on an ST', () {
    final tos100 = TosStore.identify(writeRom('a.img', 0x0100, 192))!;
    final tos104 = TosStore.identify(writeRom('b.img', 0x0104, 192))!;
    expect(TosStore.bestFor([tos100, tos104], StMachine.st), tos104);
  });

  test('an empty or missing ROM folder is not an error', () {
    expect(TosStore.scan(root.path), isEmpty);
    expect(TosStore.scan(p.join(root.path, 'nope')), isEmpty);
  });
}
