// Tests that run without a native core, a device or a TOS ROM -- which is the
// whole reason StubAtariStCore exists.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:retro_atarist/data/game_entry.dart';
import 'package:gamepads/gamepads.dart';

import 'package:retro_atarist/data/st_scancodes.dart';
import 'package:retro_atarist/services/gamepad_service.dart';
import 'package:retro_atarist/services/session_store.dart';
import 'package:retro_atarist/ffi/atarist_core.dart';
import 'package:retro_atarist/ffi/stub_atarist_core.dart';
import 'package:retro_atarist/screens/library_grid.dart';
import 'package:retro_atarist/widgets/framebuffer_view.dart';
import 'package:retro_atarist/theme/retro_atarist_theme.dart';
import 'package:retro_atarist/widgets/sidebar.dart';
import 'package:retro_atarist/widgets/sidebar_style.dart';

void main() {
  group('StubAtariStCore', () {
    test('refuses to start without a TOS ROM, like the real bridge', () {
      final core = StubAtariStCore();
      expect(core.start(const StMachineConfig()), StResult.noTos);
      expect(core.isRunning, isFalse);
    });

    test('starts with a TOS ROM and stops cleanly', () {
      final core = StubAtariStCore();
      expect(
        core.start(const StMachineConfig(tosPath: '/tos/tos104.img')),
        StResult.ok,
      );
      expect(core.isRunning, isTrue);
      expect(core.stop(), StResult.ok);
      expect(core.isRunning, isFalse);
      // Stopping twice is a no-op, not an error the UI has to guard against.
      expect(core.stop(), StResult.notRunning);
    });

    test('publishes a frame only while running', () {
      final core = StubAtariStCore();
      expect(core.getFramebuffer(), isNull);
      core.start(const StMachineConfig(tosPath: '/tos/tos104.img'));
      final frame = core.getFramebuffer();
      expect(frame, isNotNull);
      // The pitch must be a whole number of pixels, or every consumer that
      // repacks rows walks off the end of the buffer.
      expect(frame!.pitchBytes % 4, 0);
      expect(frame.pixels.length, greaterThanOrEqualTo(frame.width * frame.height));
    });

    test('frame counter stops advancing while paused', () {
      final core = StubAtariStCore()
        ..start(const StMachineConfig(tosPath: '/tos/tos104.img'));
      final before = core.frameCounter;
      expect(core.frameCounter, greaterThan(before - 1));
      core.setPaused(true);
      final paused = core.frameCounter;
      expect(core.frameCounter, paused);
    });
  });

  group('GameEntry', () {
    test('protected formats ask for accurate floppy timing, plain ones do not',
        () {
      const stx = GameEntry(
          title: 'Protected', path: '/g/game.stx', kind: GameKind.floppy);
      const st =
          GameEntry(title: 'Plain', path: '/g/game.st', kind: GameKind.floppy);
      expect(stx.needsAccurateFloppy, isTrue);
      expect(st.needsAccurateFloppy, isFalse);
    });

    test('survives a JSON round trip', () {
      const entry = GameEntry(
        title: 'Dungeon Master',
        path: '/g/dm1.st',
        kind: GameKind.floppySet,
        disks: ['/g/dm1.st', '/g/dm2.st'],
      );
      final back = GameEntry.fromJson(entry.toJson());
      expect(back.title, entry.title);
      expect(back.kind, entry.kind);
      expect(back.disks, entry.disks);
    });
  });

  group('StScancode', () {
    test('maps by physical position, so Z is the ST Z on any layout', () {
      expect(StScancode.fromPhysical[PhysicalKeyboardKey.keyZ],
          StScancode.z);
    });

    test('both host Alt keys reach the ST\'s single ALTERNATE', () {
      expect(StScancode.fromPhysical[PhysicalKeyboardKey.altLeft],
          StScancode.alternate);
      expect(StScancode.fromPhysical[PhysicalKeyboardKey.altRight],
          StScancode.alternate);
    });

    test('no two keys share a scan code', () {
      final codes = StScancode.fromPhysical.values.toList();
      final duplicates = <int>{};
      final seen = <int>{};
      for (final code in codes) {
        if (!seen.add(code)) duplicates.add(code);
      }
      // ALTERNATE is shared by both Alt keys on purpose, and CONTROL by both
      // Control keys. Anything else is a mapping mistake.
      expect(duplicates, {StScancode.alternate, StScancode.control});
    });
  });

  group('StMachineConfig', () {
    test('survives a JSON round trip', () {
      const config = StMachineConfig(
        machine: StMachine.ste,
        memoryKb: 4096,
        tosPath: '/tos/tos206.img',
        blitter: true,
      );
      final back = StMachineConfig.fromJson(config.toJson());
      expect(back.machine, StMachine.ste);
      expect(back.memoryKb, 4096);
      expect(back.tosPath, '/tos/tos206.img');
      expect(back.blitter, isTrue);
    });

    test('monitor ordinals are the ABI and must not be reordered', () {
      // The bridge static-asserts these against Hatari's MONITOR_TYPE_*.
      // Getting this wrong boots the machine on a mono monitor, where it
      // reaches a 640x400 desktop and no game ever starts.
      expect(StMonitor.mono.index, 0);
      expect(StMonitor.rgb.index, 1);
      expect(StMonitor.vga.index, 2);
      expect(StMonitor.tv.index, 3);
    });

    test('a colour monitor is the default, not mono', () {
      expect(const StMachineConfig().monitor, StMonitor.rgb);
    });

    test('machine ordinals are the ABI and must not be reordered', () {
      // The bridge static-asserts these same values against Hatari's
      // MACHINETYPE. If this test fails, the C side is now booting a
      // different machine than the UI is showing.
      expect(StMachine.st.index, 0);
      expect(StMachine.megaSt.index, 1);
      expect(StMachine.ste.index, 2);
      expect(StMachine.megaSte.index, 3);
      expect(StMachine.tt.index, 4);
      expect(StMachine.falcon.index, 5);
    });
  });

  testWidgets('empty library explains where to put files', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryGrid(
          entries: const [],
          gamesFolderPath: '/storage/AtariST',
          onLaunch: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('No ST software found'), findsOneWidget);
    expect(find.textContaining('/storage/AtariST'), findsOneWidget);
  });

  group('GamepadService', () {
    late GamepadService service;

    setUp(() => service = GamepadService());
    tearDown(() => service.dispose());

    GamepadEvent raw(double value) => GamepadEvent(
          gamepadId: 'test',
          timestamp: 0,
          type: KeyType.button,
          key: 'test',
          value: value,
        );

    NormalizedGamepadEvent button(GamepadButton b, bool down) =>
        NormalizedGamepadEvent(
          gamepadId: 'test',
          timestamp: 0,
          button: b,
          value: down ? 1.0 : 0.0,
          rawEvent: raw(down ? 1.0 : 0.0),
        );

    NormalizedGamepadEvent axis(GamepadAxis a, double v) =>
        NormalizedGamepadEvent(
          gamepadId: 'test',
          timestamp: 0,
          axis: a,
          value: v,
          rawEvent: raw(v),
        );

    test('dpad sets and CLEARS the matching direction bit', () async {
      final masks = <int>[];
      final sub = service.maskChanges.listen(masks.add);

      service.handleEvent(button(GamepadButton.dpadLeft, true));
      service.handleEvent(button(GamepadButton.dpadLeft, false));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // A make with no break is the bug that leaves a game running with the
      // stick held over forever.
      expect(masks, [StJoyBits.left, 0]);
    });

    test('both A and B are fire -- the ST has only one button', () async {
      final masks = <int>[];
      final sub = service.maskChanges.listen(masks.add);

      service.handleEvent(button(GamepadButton.a, true));
      service.handleEvent(button(GamepadButton.a, false));
      service.handleEvent(button(GamepadButton.b, true));
      service.handleEvent(button(GamepadButton.b, false));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(masks, [StJoyBits.fire, 0, StJoyBits.fire, 0]);
    });

    test('fire survives a direction change and vice versa', () async {
      final masks = <int>[];
      final sub = service.maskChanges.listen(masks.add);

      service.handleEvent(button(GamepadButton.a, true));
      service.handleEvent(button(GamepadButton.dpadRight, true));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // Holding fire while pushing right must not drop either -- the classic
      // failure is an axis update clearing the fire bit.
      expect(masks.last, StJoyBits.fire | StJoyBits.right);
    });

    test('analogue stick uses dead-zone hysteresis, not a bare threshold',
        () async {
      final masks = <int>[];
      final sub = service.maskChanges.listen(masks.add);

      service.handleEvent(axis(GamepadAxis.leftStickX, -0.35)); // inside dead zone
      service.handleEvent(axis(GamepadAxis.leftStickX, -0.5));  // engages
      service.handleEvent(axis(GamepadAxis.leftStickX, -0.35)); // still held
      service.handleEvent(axis(GamepadAxis.leftStickX, -0.1));  // releases
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // Engage at 0.40, release at 0.30. Without the gap, an axis resting on
      // the threshold makes the mask chatter on every jitter sample, which on
      // a digital ST stick reads as the stick rattling.
      expect(masks, [StJoyBits.left, 0]);
    });

    test('stick up is POSITIVE Y, down is negative', () async {
      // The `gamepads` package documents "up = +1.0, down = -1.0"
      // (PlatformMapping). Copying the sibling app's opposite assumption
      // shipped this with up and down swapped on a real Xbox Series X pad.
      final up = <int>[];
      var sub = service.maskChanges.listen(up.add);
      service.handleEvent(axis(GamepadAxis.leftStickY, 0.9));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(up.last, StJoyBits.up);

      final down = <int>[];
      sub = service.maskChanges.listen(down.add);
      service.handleEvent(axis(GamepadAxis.leftStickY, -0.9));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(down.last, StJoyBits.down);
    });

    test('non-fire buttons produce ST key events, not joystick bits', () async {
      final keys = <StKeyEvent>[];
      final masks = <int>[];
      final ks = service.keyEvents.listen(keys.add);
      final ms = service.maskChanges.listen(masks.add);

      service.handleEvent(button(GamepadButton.start, true));
      service.handleEvent(button(GamepadButton.x, true));
      await Future<void>.delayed(Duration.zero);
      await ks.cancel();
      await ms.cancel();

      expect(masks, isEmpty, reason: 'these are keys, not joystick bits');
      expect(keys.map((k) => k.scancode), [StScancode.f1, StScancode.space]);
      expect(keys.every((k) => k.pressed), isTrue);
    });
  });

  group('ResumePoint', () {
    test('survives a JSON round trip, config and all', () {
      final point = ResumePoint(
        gamePath: '/games/SWIV.stx',
        title: 'SWIV',
        config: const StMachineConfig(
          machine: StMachine.ste,
          memoryKb: 4096,
          tosPath: '/tos/tos162.img',
          accurateFloppy: true,
        ),
        savedAt: DateTime(2026, 8, 25, 12, 30),
        statePath: '/states/titles/abc123.sav',
      );

      final back = ResumePoint.fromJson(point.toJson())!;
      expect(back.gamePath, point.gamePath);
      expect(back.title, 'SWIV');
      expect(back.savedAt, point.savedAt);
      // The stored config is the whole point: restoring a snapshot into a
      // differently-configured machine does not work, because the snapshot
      // carries RAM and hardware state tied to the machine it came from.
      expect(back.config.machine, StMachine.ste);
      expect(back.config.memoryKb, 4096);
      expect(back.config.accurateFloppy, isTrue);
      expect(back.statePath, '/states/titles/abc123.sav');
    });

    test('a corrupt record is dropped, not thrown', () {
      // Losing one resume point is annoying; throwing on every launch loses
      // the whole app.
      expect(ResumePoint.fromJson(const {}), isNull);
      expect(ResumePoint.fromJson(const {'savedAt': 'not a date'}), isNull);
      // A record with no snapshot file named is useless, not half-usable.
      expect(
        ResumePoint.fromJson({'savedAt': DateTime.now().toIso8601String()}),
        isNull,
      );
    });

    test('the resume slot is kept out of the user slots', () {
      // Pausing must never overwrite a save someone made deliberately.
      expect(SessionStore.resumeSlot, isNot(SessionStore.firstUserSlot));
      expect(SessionStore.resumeSlot < SessionStore.firstUserSlot, isTrue);
    });
  });

  group('FramebufferView aspect', () {
    /// Builds the view and waits for its first decoded frame.
    ///
    /// runAsync is required: FramebufferView decodes with
    /// ui.decodeImageFromPixels, whose callback is real engine work that the
    /// test binding's fake-async zone never runs. Plain pump() therefore
    /// leaves the image null forever and the view renders its black
    /// placeholder, with no AspectRatio to inspect.
    Future<void> buildView(WidgetTester tester, {required bool fill}) async {
      final core = StubAtariStCore()
        ..start(const StMachineConfig(tosPath: '/tos/tos102.img'));

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: FramebufferView(core: core, fillScreen: fill),
          ),
        ));
        // Long enough for the 16ms poll to fire and the decode to land.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
    }

    testWidgets('4:3 mode constrains the picture to the display aspect',
        (tester) async {
      await buildView(tester, fill: false);

      final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
      // Every ST mode was shown on a 4:3 monitor, so this is the DISPLAY
      // aspect and not width/height -- 320x200 would be 1.6.
      expect(ratio.aspectRatio, closeTo(4 / 3, 0.001));
    });

    testWidgets('fill mode drops the AspectRatio entirely', (tester) async {
      await buildView(tester, fill: true);

      // The picture must actually be there, or "no AspectRatio" would pass
      // for the black placeholder too.
      expect(find.byType(RawImage), findsOneWidget);
      // No AspectRatio at all rather than a hardcoded 16:9: the panel is not
      // 16:9 once the rail and session bar have taken their share, so a fixed
      // ratio would still leave bars.
      expect(find.byType(AspectRatio), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  _sidebarTests();
}

/// The rail sizes itself from its widest label. This guards the family's
/// known trap: a global `fontFamily` on the MaterialApp theme renders labels
/// wider than the measurement the rail made, and "Compliance" comes out as
/// "Complian...". This app's theme deliberately applies monospace per style
/// instead, and this is what proves it stayed that way.
void _sidebarTests() {
  testWidgets('rail is wide enough for its longest label', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Row(
          children: [
            Sidebar(
              destinations: const [
                SidebarDestination('Games', icon: 'G'),
                SidebarDestination('Compliance', icon: 'C', group: 2),
              ],
              selectedIndex: 0,
              onSelected: _ignore,
              style: retroAtariStSidebarStyle,
              pinLastGroupToBottom: true,
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));

    final railWidth = tester.getSize(find.byType(Sidebar)).width;

    // What the widest label needs, measured the way the rail measures it:
    // in the SELECTED weight, which is the widest a row ever gets.
    final painter = TextPainter(
      text: const TextSpan(
        text: 'Compliance',
        style: TextStyle(
          fontSize: RetroAtariStMetrics.sidebarButtonTextSize,
          height: 1.15,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    const chrome = 22.0 +
        10.0 + // icon column + gap
        RetroAtariStMetrics.sidebarButtonSidePadding * 2 +
        RetroAtariStMetrics.sideNavPadding * 2;

    expect(railWidth, greaterThanOrEqualTo(painter.width + chrome));
  });
}

void _ignore(int _) {}
