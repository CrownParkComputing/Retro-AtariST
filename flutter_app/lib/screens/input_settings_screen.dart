// "Input": how the host's controls reach the ST.
import 'package:flutter/material.dart';

import '../data/st_scancodes.dart';
import '../ffi/atarist_core.dart';
import '../services/app_prefs.dart';
import '../services/gamepad_service.dart';
import '../theme/retro_atarist_theme.dart';
import '../widgets/settings_controls.dart';

class InputSettingsScreen extends StatelessWidget {
  final StMachineConfig config;
  final ValueChanged<StMachineConfig> onChanged;

  final GamepadService? gamepads;
  final OnScreenControls onScreenControls;
  final ValueChanged<OnScreenControls>? onOnScreenControlsChanged;

  const InputSettingsScreen({
    super.key,
    required this.config,
    required this.onChanged,
    this.gamepads,
    this.onScreenControls = OnScreenControls.auto,
    this.onOnScreenControlsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _controllerSection(),
        SettingsSection(
          title: 'Joystick',
          blurb: 'ST games read port 1, not port 0 -- port 0 is where the '
              'mouse lives. The launcher drives both ports; whichever one the '
              'game reads will see your input.',
          children: [
            SettingsSwitch(
              label: 'Joystick fitted',
              value: config.joystickPort1,
              onChanged: (v) => onChanged(config.copyWith(joystickPort1: v)),
            ),
          ],
        ),
        SettingsSection(
          title: 'Keyboard',
          blurb: 'Keys are sent as Atari ST scan codes, mapped by PHYSICAL '
              'position rather than by letter. A game asking for "the key '
              'left of Z" lands on the right ST key whether the host keyboard '
              'is QWERTY, AZERTY or Dvorak.',
          children: [
            _KeyNote(
              label: 'F11',
              note: 'sends HELP -- the ST key with nowhere else to sit',
            ),
            _KeyNote(
              label: 'F12',
              note: 'sends UNDO, which many games use as pause or quit',
            ),
            _KeyNote(
              label: 'Both Alt keys',
              note: 'send the ST\'s single ALTERNATE',
            ),
            const SizedBox(height: 8),
            Text(
              '${StScancode.fromPhysical.length} keys mapped.',
              style: RetroAtariStTextStyles.statusLine,
            ),
          ],
        ),
        const SettingsSection(
          title: 'Mouse',
          blurb: 'The ST mouse is relative, like a real one: there is no '
              'absolute position to jump to. On a touch screen, drag to move '
              'the pointer rather than tapping where you want it.',
          children: [],
        ),
      ],
    );
  }
}

extension on InputSettingsScreen {
  Widget _controllerSection() {
    final service = gamepads;
    return SettingsSection(
      title: 'Controller',
      blurb: 'The ST joystick is four directions and ONE fire button, so both '
          'bottom face buttons send fire. The rest of the pad has nothing on '
          'the joystick port to drive, and is mapped to the keys ST games '
          'actually use for start and secondary actions.',
      children: [
        if (service != null)
          // Live, not a snapshot: plugging a pad in should be visible here
          // without leaving the screen, because this is where someone looks
          // when the pad "does not work".
          ValueListenableBuilder<bool>(
            valueListenable: service.connected,
            builder: (context, connected, _) => ValueListenableBuilder<List<String>>(
              valueListenable: service.names,
              builder: (context, names, _) => _DetectionRow(
                connected: connected,
                names: names,
              ),
            ),
          ),
        if (onOnScreenControlsChanged != null)
          SettingsDropdown<OnScreenControls>(
            label: 'On-screen stick',
            value: onScreenControls,
            options: OnScreenControls.values,
            labelOf: (m) => m.label,
            blurbOf: (m) => m.blurb,
            onChanged: onOnScreenControlsChanged!,
          ),
        const SizedBox(height: 6),
        const _PadMapping('D-pad / left stick', 'joystick directions'),
        const _PadMapping('A or B', 'FIRE'),
        const _PadMapping('X', 'SPACE'),
        const _PadMapping('Y', 'RETURN'),
        const _PadMapping('Start', 'F1 -- starts a startling number of ST games'),
        const _PadMapping('Back / Select', 'ESC'),
        const _PadMapping('L1 / R1', 'F2 / SPACE'),
      ],
    );
  }
}

class _DetectionRow extends StatelessWidget {
  final bool connected;
  final List<String> names;

  const _DetectionRow({required this.connected, required this.names});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            connected ? Icons.videogame_asset : Icons.videogame_asset_off,
            size: 18,
            color: connected
                ? RetroAtariStColors.accentDesktopGreen
                : RetroAtariStColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connected
                  ? (names.isEmpty ? 'Controller connected' : names.join(', '))
                  : 'No controller detected',
              style: TextStyle(
                fontSize: 12,
                color: connected
                    ? RetroAtariStColors.accentDesktopGreen
                    : RetroAtariStColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PadMapping extends StatelessWidget {
  final String button;
  final String action;

  const _PadMapping(this.button, this.action);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(button,
                style: const TextStyle(
                    color: RetroAtariStColors.textMuted2, fontSize: 11)),
          ),
          Expanded(
            child: Text(action, style: RetroAtariStTextStyles.statusLine),
          ),
        ],
      ),
    );
  }
}

class _KeyNote extends StatelessWidget {
  final String label;
  final String note;

  const _KeyNote({required this.label, required this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: RetroAtariStColors.coverFill,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: RetroAtariStColors.coverStroke),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(note, style: RetroAtariStTextStyles.statusLine),
          ),
        ],
      ),
    );
  }
}
