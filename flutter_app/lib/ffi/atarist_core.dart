// The emulator core as the UI sees it.
//
// Everything above this line is plain Dart: screens, widgets and the save
// state service talk to an [AtariStCore], never to dart:ffi directly. There
// are two implementations:
//
//   - AtariStCoreBindings (atarist_bindings.dart), which opens
//     libatarist_core.so. That class cannot even be constructed without the
//     native library on disk, which is why this interface exists rather than
//     the concrete type being referenced everywhere.
//   - StubAtariStCore (stub_atarist_core.dart), which reports "not running"
//     for everything and draws a GEM-desktop-ish test pattern.
//
// The stub is not just a test fake. The native core is a separate, slow build
// (Hatari plus this project's backend and bridge), so the whole Flutter UI is
// developed and run against the stub, and `flutter test` needs no native
// library, no device, no TOS ROM and no game files.
import 'dart:typed_data';

/// One frame, as the UI receives it.
class StFrame {
  final int width;
  final int height;

  /// Row stride in BYTES. Not width * 4: the core renders into a
  /// fixed-stride buffer sized for the widest overscan mode, and a narrow
  /// mode occupies the left of each row. Treating this as width*4 produces
  /// the classic diagonally-sheared emulator screenshot.
  final int pitchBytes;

  /// XRGB8888, one uint32 per pixel.
  final Uint32List pixels;

  const StFrame({
    required this.width,
    required this.height,
    required this.pitchBytes,
    required this.pixels,
  });
}

/// The machine to boot. Mirrors AtariStConfig in atarist_bridge.h.
class StMachineConfig {
  final StMachine machine;

  /// ST RAM in kilobytes. Null means "Hatari's default for this machine".
  final int? memoryKb;

  /// TOS ROM image. Required: the ST cannot boot without one, and it is
  /// copyrighted by Atari so the app never ships one -- exactly as with the
  /// C64 KERNAL in Retro-C64.
  final String? tosPath;

  final String? floppyA;
  final String? floppyB;

  /// A host directory mapped as an ST hard disk through GEMDOS emulation.
  /// This is how most modern ST software is run: no image file, just a
  /// folder.
  final String? gemdosDir;

  final String? acsiImage;
  final String? ideImage;

  final bool blitter;

  /// false = fast floppy (boots in seconds, the sane default), true =
  /// cycle-accurate FDC timing, which protected originals need and which
  /// makes a load take as long as it did in 1988.
  final bool accurateFloppy;

  final int sampleRate;
  final bool stereo;

  /// The monitor fitted to the machine.
  ///
  /// Not cosmetic: TOS reads the monitor type at boot and picks its screen
  /// mode from it. On a mono monitor the machine comes up in ST-HIGH --
  /// 640x400, two colours -- where essentially no game runs. It boots, it
  /// draws, it reaches a desktop, and the game never appears.
  final StMonitor monitor;

  final bool joystickPort1;

  const StMachineConfig({
    this.machine = StMachine.st,
    this.memoryKb,
    this.tosPath,
    this.floppyA,
    this.floppyB,
    this.gemdosDir,
    this.acsiImage,
    this.ideImage,
    this.blitter = false,
    this.accurateFloppy = false,
    this.sampleRate = 44100,
    this.stereo = true,
    this.monitor = StMonitor.rgb,
    this.joystickPort1 = true,
  });

  StMachineConfig copyWith({
    StMachine? machine,
    int? memoryKb,
    String? tosPath,
    String? floppyA,
    String? floppyB,
    String? gemdosDir,
    String? acsiImage,
    String? ideImage,
    bool? blitter,
    bool? accurateFloppy,
    int? sampleRate,
    bool? stereo,
    StMonitor? monitor,
    bool? joystickPort1,
  }) {
    return StMachineConfig(
      machine: machine ?? this.machine,
      memoryKb: memoryKb ?? this.memoryKb,
      tosPath: tosPath ?? this.tosPath,
      floppyA: floppyA ?? this.floppyA,
      floppyB: floppyB ?? this.floppyB,
      gemdosDir: gemdosDir ?? this.gemdosDir,
      acsiImage: acsiImage ?? this.acsiImage,
      ideImage: ideImage ?? this.ideImage,
      blitter: blitter ?? this.blitter,
      accurateFloppy: accurateFloppy ?? this.accurateFloppy,
      sampleRate: sampleRate ?? this.sampleRate,
      stereo: stereo ?? this.stereo,
      monitor: monitor ?? this.monitor,
      joystickPort1: joystickPort1 ?? this.joystickPort1,
    );
  }

  Map<String, dynamic> toJson() => {
        'machine': machine.name,
        if (memoryKb != null) 'memoryKb': memoryKb,
        if (tosPath != null) 'tosPath': tosPath,
        if (floppyA != null) 'floppyA': floppyA,
        if (floppyB != null) 'floppyB': floppyB,
        if (gemdosDir != null) 'gemdosDir': gemdosDir,
        if (acsiImage != null) 'acsiImage': acsiImage,
        if (ideImage != null) 'ideImage': ideImage,
        'blitter': blitter,
        'accurateFloppy': accurateFloppy,
        'sampleRate': sampleRate,
        'stereo': stereo,
        'monitor': monitor.name,
        'joystickPort1': joystickPort1,
      };

  factory StMachineConfig.fromJson(Map<String, dynamic> json) {
    return StMachineConfig(
      machine: StMachine.values.firstWhere(
        (m) => m.name == json['machine'],
        orElse: () => StMachine.st,
      ),
      memoryKb: json['memoryKb'] as int?,
      tosPath: json['tosPath'] as String?,
      floppyA: json['floppyA'] as String?,
      floppyB: json['floppyB'] as String?,
      gemdosDir: json['gemdosDir'] as String?,
      acsiImage: json['acsiImage'] as String?,
      ideImage: json['ideImage'] as String?,
      blitter: (json['blitter'] as bool?) ?? false,
      accurateFloppy: (json['accurateFloppy'] as bool?) ?? false,
      sampleRate: (json['sampleRate'] as int?) ?? 44100,
      stereo: (json['stereo'] as bool?) ?? true,
      monitor: StMonitor.values.firstWhere(
        (m) => m.name == json['monitor'],
        orElse: () => StMonitor.rgb,
      ),
      joystickPort1: (json['joystickPort1'] as bool?) ?? true,
    );
  }
}

/// The machines Hatari emulates, in the order ATARIST_MACHINE_* declares them.
///
/// The ordinal is the ABI value, so this list must not be reordered. The
/// bridge asserts the same mapping against Hatari's own MACHINETYPE at compile
/// time, which is what stops a reordering upstream from silently booting a
/// Falcon when the user picked an STE.
enum StMachine {
  st('ST', 'The 1985 original. 512K or 1MB, no Blitter.'),
  megaSt('Mega ST', 'ST in a desktop case, with a Blitter and a real clock.'),
  ste('STE', 'Blitter, 4096 colours, DMA stereo sound and analogue ports.'),
  megaSte('Mega STE', '16MHz 68000 STE in a desktop case.'),
  tt('TT030', '32MHz 68030 workstation. Very few games.'),
  falcon('Falcon 030', '68030 with a DSP. Almost no ST game needs it.');

  final String label;
  final String blurb;
  const StMachine(this.label, this.blurb);

  /// Only the first three are worth offering by default. A TT or a Falcon
  /// will run a plain ST game, but slightly differently and much more slowly,
  /// and offering six equal-looking choices to someone who just wants to play
  /// a 1988 game is a way to get it wrong.
  static const List<StMachine> common = [st, megaSt, ste];
}

/// Monitors, in the order ATARIST_MONITOR_* declares them. The ordinal is the
/// ABI value, so this list must not be reordered.
enum StMonitor {
  mono('High-res mono', 'ST-HIGH 640x400. Right for desktop applications, '
      'wrong for almost every game.'),
  rgb('Colour (RGB)', 'The colour monitor nearly every ST game expects.'),
  vga('VGA', 'Falcon and TT only.'),
  tv('TV', 'The colour picture through the RF modulator.');

  final String label;
  final String blurb;
  const StMonitor(this.label, this.blurb);
}

/// Result codes, mirroring the #defines in atarist_bridge.h.
class StResult {
  StResult._();

  static const int ok = 0;
  static const int err = -1;

  /// The emulation thread did not service a mailbox request in time.
  static const int timeout = -2;

  static const int notRunning = -3;

  /// A core is already up. Stop it before starting another.
  static const int alreadyStarted = -4;

  /// No usable TOS ROM. By far the most common launch failure, so it has its
  /// own code and its own message in the UI.
  static const int noTos = -5;

  static String describe(int code) {
    switch (code) {
      case ok:
        return 'OK';
      case timeout:
        return 'The emulator stopped responding.';
      case notRunning:
        return 'No machine is running.';
      case alreadyStarted:
        return 'A machine is already running.';
      case noTos:
        return 'No TOS ROM is set. The ST cannot boot without one -- '
            'add one under Machine.';
      default:
        return 'The emulator reported an error.';
    }
  }
}

class StLimits {
  StLimits._();

  /// ATARIST_SLOT_COUNT in atarist_bridge.h.
  static const int slotCount = 10;
}

/// Emulated ST joystick bits, matching the ATARIST_JOY_* defines.
///
/// Note the gap: fire is 0x80, not 0x10. That is the hardware's own layout
/// (the ST reads the port's four direction bits and the fire bit from
/// different halves of the byte), not an arbitrary choice, so do not "tidy" it.
class StJoyBits {
  StJoyBits._();

  static const int up = 0x01;
  static const int down = 0x02;
  static const int left = 0x04;
  static const int right = 0x08;
  static const int fire = 0x80;
}

abstract class AtariStCore {
  /// [workDir] is where the core may write (its config, NVRAM, save states);
  /// [tosDir] is where bundled TOS/EmuTOS images live. Must be called before
  /// [start].
  void init(String workDir, String tosDir);

  /// Boots the machine described by [config].
  ///
  /// Asynchronous: the ST is still executing TOS's startup when this returns,
  /// so the caller must not expect a frame immediately. Returns one of
  /// [StResult].
  int start(StMachineConfig config);

  /// Stops the machine and joins the emulation thread. Unlike DOSBox-X, a
  /// later [start] does work -- Hatari tears down cleanly.
  int stop();

  bool get isRunning;

  /// Whether the UI has asked the core to pause.
  bool get isPaused;

  void setPaused(bool paused);

  /// Cold reset is a power cycle; warm reset is the ST's reset button.
  int reset({bool cold = true});

  // --- Media ---------------------------------------------------------------

  /// Inserts or ejects a floppy while the machine runs -- what a multi-disk
  /// game's "insert disk 2" prompt needs. [path] null ejects.
  int setFloppy(int drive, String? path);

  String? getFloppy(int drive);

  // --- Input ---------------------------------------------------------------

  /// Keyboard by ATARI ST scan code (see data/st_scancodes.dart), not by
  /// host keycode and not by character: ST games read the IKBD's make/break
  /// codes directly, so anything higher-level loses the key-up half and
  /// leaves a game running with a direction held down forever.
  void keyEvent(int stScancode, bool pressed);

  void mouseMotion(int dx, int dy);

  /// button: 0 left, 1 right.
  void mouseButton(int button, bool pressed);

  /// port: 0 or 1. mask: bitwise OR of [StJoyBits].
  void joystick(int port, int mask);

  // --- Save states ---------------------------------------------------------

  int saveState(int slot);
  int loadState(int slot);

  /// The same, to a caller-chosen file.
  ///
  /// Slots are one global set, which is wrong for per-title auto-saves:
  /// closing one game would overwrite the position of the last one. These
  /// keep a state file per title instead.
  int saveStateTo(String path);
  int loadStateFrom(String path);

  /// null when the slot could not be queried.
  bool? stateIsEmpty(int slot);

  // --- Status --------------------------------------------------------------

  int get fps;

  /// Smoothed 0..100 output peak, for level meters.
  int get audioLevel;

  /// Drive lights and the core's own messages, or null.
  String? get statusLine;

  /// The last error the core reported, or null.
  String? get lastError;

  /// The current frame, or null before the core has drawn one.
  StFrame? getFramebuffer();

  /// Bumped once per completed frame. Lets the UI skip the copy and texture
  /// upload when nothing changed -- a GEM desktop sitting idle is
  /// byte-identical for minutes at a time.
  int get frameCounter;

  /// Display aspect ratio for the current mode, or null if unknown.
  ///
  /// Not width/height. Every ST mode was shown on a 4:3 monitor, so 320x200,
  /// 640x200 and 640x400 all have differently-shaped pixels, and only
  /// stretching to the display aspect keeps a circle round in all three.
  double? get pixelAspect;

  /// Hatari's version, for the About screen. Null on the stub.
  String? get coreVersion;

  /// Which audio backend was compiled in and opened -- "SDL3", "SDL2" or
  /// "none". Reported on About because "no sound" and "no audio sink exists
  /// on this platform yet" are indistinguishable from the speakers.
  String? get audioBackend;
}
