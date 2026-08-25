// "Machine": which ST is being emulated, and the TOS ROM it boots.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ffi/atarist_core.dart';
import '../services/tos_store.dart';
import '../theme/retro_atarist_theme.dart';
import '../widgets/settings_controls.dart';

class MachineSettingsScreen extends StatelessWidget {
  final StMachineConfig config;
  final ValueChanged<StMachineConfig> onChanged;

  /// Set when this sheet is editing ONE title's override rather than the
  /// app-wide default, so the screen can say which.
  final String? titleName;

  /// TOS ROMs found in the app's ROM folder, identified by header rather than
  /// by filename. Offered as a dropdown so the common case is a choice from a
  /// list rather than a trip through a file picker.
  final List<TosRom> availableRoms;

  /// Where those ROMs live, so the empty state can say where to put one.
  final String? tosDir;

  const MachineSettingsScreen({
    super.key,
    required this.config,
    required this.onChanged,
    this.titleName,
    this.availableRoms = const <TosRom>[],
    this.tosDir,
  });

  /// The memory sizes the ST family actually shipped or could be expanded to.
  /// A free-text field would let someone type 3000 and get a machine that
  /// boots to a bus error.
  static const List<int> _memorySizes = [512, 1024, 2048, 4096, 8192, 14336];

  static String _memoryLabel(int kb) =>
      kb >= 1024 ? '${kb ~/ 1024} MB' : '$kb KB';

  Future<void> _pickTos(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a TOS ROM image',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path != null) onChanged(config.copyWith(tosPath: path));
  }

  /// A warning when the selected ROM does not suit the selected machine.
  ///
  /// Worth stating in advance because the failure is not subtle and does not
  /// look like a ROM problem: a TOS 1.02 image on an STE halts the CPU with a
  /// double bus fault, which surfaces as "the emulated CPU halted" and reads
  /// as an emulator bug.
  String? _romBlurb() {
    final selected = _selectedRom();
    if (selected == null) {
      return availableRoms.isEmpty
          ? 'TOS 1.00-1.04 for ST and Mega ST; 1.06-2.06 for STE.'
          : null;
    }
    if (!selected.suitableFor.contains(config.machine)) {
      return 'This ROM is not for a ${config.machine.label}. The machine will '
          'halt on boot -- pick another ROM or another model.';
    }
    return null;
  }

  TosRom? _selectedRom() {
    final path = config.tosPath;
    if (path == null || path.isEmpty) return null;
    for (final rom in availableRoms) {
      if (rom.path == path) return rom;
    }
    return null;
  }

  Widget _romDropdown() {
    final selected = _selectedRom();
    return SettingsDropdown<String>(
      label: 'Installed ROM',
      // Keyed by path, not by TosRom: the dropdown compares values with ==,
      // and two TosRom instances describing the same file are not equal.
      value: selected?.path ?? '',
      options: ['', ...availableRoms.map((r) => r.path)],
      labelOf: (path) {
        if (path.isEmpty) return 'none selected';
        for (final rom in availableRoms) {
          if (rom.path == path) return '${rom.label}  --  ${rom.fileName}';
        }
        return path;
      },
      onChanged: (path) => onChanged(config.copyWith(tosPath: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (titleName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Settings for $titleName',
                style: RetroAtariStTextStyles.statusLine),
          ),
        SettingsSection(
          title: 'Hardware',
          blurb: 'Most 1985-1990 games were written for a 512K or 1MB plain '
              'ST. Picking a bigger machine rarely helps and occasionally '
              'breaks a title that checks what it is running on.',
          children: [
            SettingsDropdown<StMachine>(
              label: 'Model',
              value: config.machine,
              options: StMachine.values,
              labelOf: (m) => m.label,
              blurbOf: (m) => m.blurb,
              onChanged: (m) => onChanged(config.copyWith(machine: m)),
            ),
            SettingsDropdown<int>(
              label: 'Memory',
              value: config.memoryKb ?? 1024,
              options: _memorySizes,
              labelOf: _memoryLabel,
              onChanged: (kb) => onChanged(config.copyWith(memoryKb: kb)),
            ),
            SettingsDropdown<StMonitor>(
              label: 'Monitor',
              value: config.monitor,
              options: StMonitor.values,
              labelOf: (m) => m.label,
              blurbOf: (m) => m.blurb,
              onChanged: (m) => onChanged(config.copyWith(monitor: m)),
            ),
            SettingsSwitch(
              label: 'Blitter',
              blurb: 'Mega ST and STE hardware. Enabling it on a plain ST is '
                  'a Hatari extension some demos ask for.',
              value: config.blitter,
              onChanged: (v) => onChanged(config.copyWith(blitter: v)),
            ),
          ],
        ),
        SettingsSection(
          title: 'TOS ROM',
          blurb: 'The ST cannot boot without one. TOS is copyrighted by '
              'Atari, so this app does not ship it -- supply your own image, '
              'the same as the KERNAL in Retro-C64.',
          children: [
            if (availableRoms.isNotEmpty) _romDropdown(),
            SettingsPath(
              label: availableRoms.isEmpty ? 'ROM image' : 'Or a file',
              value: config.tosPath,
              emptyText: 'not set -- nothing will boot',
              blurb: _romBlurb(),
              onPick: () => _pickTos(context),
              onClear: () => onChanged(config.copyWith(tosPath: '')),
            ),
          ],
        ),
        SettingsSection(
          title: 'Sound',
          children: [
            SettingsDropdown<int>(
              label: 'Sample rate',
              value: config.sampleRate,
              options: const [22050, 32000, 44100, 48000],
              labelOf: (r) => '$r Hz',
              onChanged: (r) => onChanged(config.copyWith(sampleRate: r)),
            ),
            SettingsSwitch(
              label: 'Stereo',
              blurb: "The YM2149 is mono; the STE's DMA sound is stereo.",
              value: config.stereo,
              onChanged: (v) => onChanged(config.copyWith(stereo: v)),
            ),
          ],
        ),
      ],
    );
  }
}
