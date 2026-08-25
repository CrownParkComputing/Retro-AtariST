// A core that emulates nothing.
//
// Not only a test fake. The native core is a separate, slow build (Hatari plus
// this project's backend and bridge), so the whole Flutter UI is developed and
// run against this, and `flutter test` needs no native library, no device, no
// TOS ROM and no disk images.
//
// It draws a recognisable GEM-desktop-like pattern rather than a black screen
// or noise, because the two failures it has to be distinguishable from are "the
// emulator is running but the game has not drawn yet" (black) and "the
// framebuffer is being read at the wrong stride" (noise). A deliberate, obviously
// synthetic image is neither.
import 'dart:typed_data';

import 'atarist_core.dart';

class StubAtariStCore implements AtariStCore {
  static const int _width = 320;
  static const int _height = 200;

  bool _running = false;
  bool _paused = false;
  int _frame = 0;
  StMachineConfig? _config;
  final List<String?> _floppies = <String?>[null, null];
  final Set<int> _occupiedSlots = <int>{};

  @override
  void init(String workDir, String tosDir) {}

  @override
  int start(StMachineConfig config) {
    if (_running) return StResult.alreadyStarted;
    // The same TOS check the real bridge makes, so the "no ROM yet" path in
    // the UI can be exercised without a native build.
    if (config.tosPath == null || config.tosPath!.isEmpty) {
      return StResult.noTos;
    }
    _config = config;
    _running = true;
    _paused = false;
    _frame = 1;
    _floppies[0] = config.floppyA;
    _floppies[1] = config.floppyB;
    return StResult.ok;
  }

  @override
  int stop() {
    if (!_running) return StResult.notRunning;
    _running = false;
    _frame = 0;
    return StResult.ok;
  }

  @override
  bool get isRunning => _running;

  @override
  bool get isPaused => _paused;

  @override
  void setPaused(bool paused) => _paused = paused;

  @override
  int reset({bool cold = true}) =>
      _running ? StResult.ok : StResult.notRunning;

  @override
  int setFloppy(int drive, String? path) {
    if (!_running) return StResult.notRunning;
    if (drive < 0 || drive > 1) return StResult.err;
    _floppies[drive] = path;
    return StResult.ok;
  }

  @override
  String? getFloppy(int drive) =>
      (drive >= 0 && drive <= 1) ? _floppies[drive] : null;

  @override
  void keyEvent(int stScancode, bool pressed) {}

  @override
  void mouseMotion(int dx, int dy) {}

  @override
  void mouseButton(int button, bool pressed) {}

  @override
  void joystick(int port, int mask) {}

  @override
  int saveState(int slot) {
    if (!_running) return StResult.notRunning;
    _occupiedSlots.add(slot);
    return StResult.ok;
  }

  @override
  int loadState(int slot) {
    if (!_running) return StResult.notRunning;
    return _occupiedSlots.contains(slot) ? StResult.ok : StResult.err;
  }

  @override
  bool? stateIsEmpty(int slot) => !_occupiedSlots.contains(slot);

  /// Paths the stub pretends to have written, so the resume flow can be
  /// exercised with no native core and no files on disk.
  final Set<String> _statePaths = <String>{};

  @override
  int saveStateTo(String path) {
    if (!_running) return StResult.notRunning;
    _statePaths.add(path);
    return StResult.ok;
  }

  @override
  int loadStateFrom(String path) {
    if (!_running) return StResult.notRunning;
    return _statePaths.contains(path) ? StResult.ok : StResult.err;
  }

  @override
  int get fps => _running && !_paused ? 50 : 0;

  @override
  int get audioLevel => 0;

  @override
  String? get statusLine =>
      _running ? 'stub core -- ${_config?.machine.label ?? "ST"}' : null;

  @override
  String? get lastError => null;

  @override
  int get frameCounter {
    // Advances only while running and unpaused, so the UI's
    // "skip the upload when nothing changed" path is exercised too.
    if (_running && !_paused) _frame++;
    return _frame;
  }

  @override
  double? get pixelAspect => _running ? 4 / 3 : null;

  @override
  String? get coreVersion => null;

  @override
  String? get audioBackend => null;

  @override
  StFrame? getFramebuffer() {
    if (!_running) return null;

    final pixels = Uint32List(_width * _height);
    // The GEM desktop's green, with a lighter menu bar across the top and a
    // slowly moving marker so a frozen frame is visibly frozen.
    const desktop = 0xFF008000;
    const menuBar = 0xFFC0C0C0;
    const marker = 0xFFE1141C;

    for (var y = 0; y < _height; y++) {
      final row = y * _width;
      final base = y < 16 ? menuBar : desktop;
      for (var x = 0; x < _width; x++) {
        pixels[row + x] = base;
      }
    }

    final markerX = (_frame ~/ 2) % (_width - 16);
    for (var y = 96; y < 112; y++) {
      for (var x = markerX; x < markerX + 16; x++) {
        pixels[y * _width + x] = marker;
      }
    }

    return StFrame(
      width: _width,
      height: _height,
      pitchBytes: _width * 4,
      pixels: pixels,
    );
  }
}
