// External gamepad support, feeding the emulated ST joystick.
//
// Flutter has no first-party controller API, so this uses the `gamepads`
// package (github.com/flame-engine/gamepads), which covers Linux, Android,
// iOS, macOS and Windows with a normalised button/axis model.
//
// Ported from Retro-Dosbox's service, with the PC-specific half removed. The
// difference matters more than it looks: a PC game port is four buttons and
// two analogue axes, and DOS games read both. **The Atari ST's DE-9 port is
// four digital direction lines and ONE fire button.** There is nothing analogue
// to forward -- so this service produces a bare mask, and the analogue stick is
// only ever a source of direction BITS.
//
// That leaves the pad's other buttons with nothing to drive, which is why they
// are mapped to ST keys instead. ST games overwhelmingly use SPACE, RETURN and
// F1 for start/secondary actions -- the ST's single fire button is why -- so a
// pad whose face buttons all did the same thing would waste most of itself.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';

import '../data/st_scancodes.dart';
import '../ffi/atarist_core.dart';

/// One ST key press or release produced by a pad button.
class StKeyEvent {
  final int scancode;
  final bool pressed;
  const StKeyEvent(this.scancode, this.pressed);
}

class GamepadService {
  StreamSubscription<NormalizedGamepadEvent>? _sub;
  Timer? _pollTimer;
  Timer? _refreshTimer;

  final _maskController = StreamController<int>.broadcast();
  final _keyController = StreamController<StKeyEvent>.broadcast();

  int _mask = 0;
  double _axisX = 0;
  double _axisY = 0;

  /// Whether any controller is currently connected.
  ///
  /// Polled rather than streamed because the package exposes no
  /// connect/disconnect event. This is what auto-hides the on-screen stick,
  /// so it is deliberately a [ValueNotifier] the UI can rebuild on.
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// Names of the connected pads, for the Input screen to show. Without it,
  /// "no controller detected" is indistinguishable from "detected, but the
  /// mapping is wrong".
  final ValueNotifier<List<String>> names = ValueNotifier(const []);

  /// The ST joystick mask (see [StJoyBits]).
  Stream<int> get maskChanges => _maskController.stream;

  /// ST key presses from the pad's non-fire buttons.
  Stream<StKeyEvent> get keyEvents => _keyController.stream;

  void start() {
    _sub = Gamepads.normalizedEvents.listen(handleEvent, onError: (_) {
      // Best-effort: some platforms and sandboxes cannot enumerate gamepads
      // at all (no /dev/input access, no permission). Swallow rather than
      // take the emulator screen down with it.
    });
    _pollConnection();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _pollConnection());

    // Re-send the held state on a tight interval.
    //
    // Pad buttons report one down and one up with no auto-repeat, so a held
    // direction produces no events at all for the duration of the hold. The
    // bridge stores the joystick as a level rather than a queue so it would
    // survive that -- but re-sending costs nothing and makes the service
    // robust against a dropped event leaving a direction stuck on.
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        if (!_maskController.isClosed) _maskController.add(_mask);
      },
    );
  }

  Future<void> _pollConnection() async {
    try {
      final list = await Gamepads.list();
      final next = list.isNotEmpty;
      if (next != connected.value) {
        // Logged because this value silently decides whether the on-screen
        // stick appears: in `auto` mode a controller that is detected but
        // unusable makes the pad vanish with no way to tell why from the
        // screen alone.
        debugPrint('atarist: controllers=${list.length} '
            '[${list.map((g) => '${g.id}/${g.name}').join(', ')}]');
      }
      connected.value = next;
      names.value = list.map((g) => g.name).toList(growable: false);
    } catch (_) {
      // See start()'s onError comment.
    }
  }

  /// Dead-zone hysteresis for the analogue stick.
  ///
  /// Engage when the axis crosses [_engage]; release only when it falls back
  /// past [_release]. The gap stops the mask flickering when the axis sits
  /// right on the threshold and hardware jitter crosses it every sample --
  /// which on a digital ST joystick reads as the stick rattling.
  static const double _engage = 0.40;
  static const double _release = 0.30;

  static const int _directionBits =
      StJoyBits.up | StJoyBits.down | StJoyBits.left | StJoyBits.right;

  /// Recompute the direction bits from the analogue axes, leaving fire alone.
  ///
  /// **Stick UP is POSITIVE Y.** That is the `gamepads` package's documented
  /// contract ("Normalized stick Y values use up = +1.0, down = -1.0" --
  /// PlatformMapping), enforced on Linux/Windows by the `yAxisInverted` flag
  /// in its controller database.
  ///
  /// The sibling Retro-Dosbox service assumes the opposite, and copying it is
  /// what shipped this app with up and down swapped on a real Xbox Series X
  /// pad. Screen coordinates run the other way and that intuition is very
  /// hard to shake, so: positive is up, and the test below pins it.
  int _deriveMask(double x, double y, int currentMask) {
    var m = currentMask & ~_directionBits;
    bool held(int bit) => (currentMask & bit) != 0;

    if (held(StJoyBits.left)) {
      if (x <= -_release) m |= StJoyBits.left;
    } else if (x < -_engage) {
      m |= StJoyBits.left;
    }
    if (held(StJoyBits.right)) {
      if (x >= _release) m |= StJoyBits.right;
    } else if (x > _engage) {
      m |= StJoyBits.right;
    }
    if (held(StJoyBits.up)) {
      if (y >= _release) m |= StJoyBits.up;
    } else if (y > _engage) {
      m |= StJoyBits.up;
    }
    if (held(StJoyBits.down)) {
      if (y <= -_release) m |= StJoyBits.down;
    } else if (y < -_engage) {
      m |= StJoyBits.down;
    }
    return m;
  }

  void _emitMask(int next) {
    if (next == _mask) return;
    _mask = next;
    if (!_maskController.isClosed) _maskController.add(next);
  }

  int _withBit(int mask, int bit, bool on) =>
      on ? mask | bit : mask & ~bit;

  /// Pad buttons that are not fire, mapped to ST keys.
  ///
  /// The ST has ONE joystick button, so everything else has to become a
  /// keystroke to be worth anything. These are the keys ST games actually
  /// use for start and secondary actions -- F1 in particular starts a
  /// startling proportion of them.
  static const Map<GamepadButton, int> buttonKeys = {
    GamepadButton.x: StScancode.space,
    GamepadButton.y: StScancode.enter,
    GamepadButton.start: StScancode.f1,
    GamepadButton.back: StScancode.escape,
    GamepadButton.leftBumper: StScancode.f2,
    GamepadButton.rightBumper: StScancode.space,
  };

  /// Folds one normalised pad event into the joystick state.
  ///
  /// Public and directly tested because the axis convention is exactly the
  /// sort of thing that gets guessed wrong -- in the sibling app the stick Y
  /// axis WAS guessed wrong, and up/down came out swapped on every real pad
  /// until someone plugged one in.
  @visibleForTesting
  void handleEvent(NormalizedGamepadEvent event) {
    final button = event.button;
    if (button != null) {
      final down = event.value != 0;
      switch (button) {
        case GamepadButton.dpadUp:
          _axisY = down ? 1.0 : 0.0;
          _emitMask(_withBit(_mask, StJoyBits.up, down));
          return;
        case GamepadButton.dpadDown:
          _axisY = down ? -1.0 : 0.0;
          _emitMask(_withBit(_mask, StJoyBits.down, down));
          return;
        case GamepadButton.dpadLeft:
          _axisX = down ? -1.0 : 0.0;
          _emitMask(_withBit(_mask, StJoyBits.left, down));
          return;
        case GamepadButton.dpadRight:
          _axisX = down ? 1.0 : 0.0;
          _emitMask(_withBit(_mask, StJoyBits.right, down));
          return;

        // BOTH bottom face buttons are fire. The ST has one button and no
        // convention about which pad button stands in for it, so honouring
        // only A leaves half of everyone pressing a dead button.
        case GamepadButton.a:
        case GamepadButton.b:
          _emitMask(_withBit(_mask, StJoyBits.fire, down));
          return;

        default:
          final scancode = buttonKeys[button];
          if (scancode != null && !_keyController.isClosed) {
            _keyController.add(StKeyEvent(scancode, down));
          }
          return;
      }
    }

    final axis = event.axis;
    if (axis == GamepadAxis.leftStickX) {
      _axisX = event.value;
    } else if (axis == GamepadAxis.leftStickY) {
      _axisY = event.value;
    } else {
      return;
    }
    _emitMask(_deriveMask(_axisX, _axisY, _mask));
  }

  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    _refreshTimer?.cancel();
    _maskController.close();
    _keyController.close();
    connected.dispose();
    names.dispose();
  }
}
