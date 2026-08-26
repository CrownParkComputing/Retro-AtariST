// "Media": what is in the drives.
//
// Separate from Machine because these change per session and often mid-game
// (a multi-disk title asking for disk 2), while the machine settings are set
// once and forgotten.
import '../services/storage_permission.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ffi/atarist_core.dart';
import '../widgets/settings_controls.dart';

class MediaSettingsScreen extends StatelessWidget {
  final StMachineConfig config;
  final ValueChanged<StMachineConfig> onChanged;

  /// Non-null while a machine is running, so a disk can be swapped live
  /// rather than only configured for the next launch.
  final AtariStCore? runningCore;

  const MediaSettingsScreen({
    super.key,
    required this.config,
    required this.onChanged,
    this.runningCore,
  });

  Future<String?> _pickFile(String title) async {
    final result = await FilePicker.platform.pickFiles(dialogTitle: title);
    return result?.files.single.path;
  }

  Future<void> _setFloppy(int drive, String? path) async {
    onChanged(drive == 0
        ? config.copyWith(floppyA: path ?? '')
        : config.copyWith(floppyB: path ?? ''));

    // Applied to the running machine too. Without this, "insert disk 2" would
    // set up the NEXT launch and do nothing to the game currently asking for
    // it, which reads as the button being broken.
    final core = runningCore;
    if (core != null && core.isRunning) {
      core.setFloppy(drive, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = runningCore?.isRunning ?? false;
    return ListView(
      children: [
        SettingsSection(
          title: 'Floppy drives',
          blurb: live
              ? 'A machine is running: changing a disk here inserts it now.'
              : 'Disks are inserted when the machine next starts.',
          children: [
            SettingsPath(
              label: 'Drive A',
              value: config.floppyA,
              emptyText: 'empty',
              onPick: () async {
                final path = await _pickFile('Choose a disk image for drive A');
                if (path != null) await _setFloppy(0, path);
              },
              onClear: () => _setFloppy(0, null),
            ),
            SettingsPath(
              label: 'Drive B',
              value: config.floppyB,
              emptyText: 'empty',
              blurb: 'A second drive. Multi-disk games load noticeably faster '
                  'with disk 2 already in it.',
              onPick: () async {
                final path = await _pickFile('Choose a disk image for drive B');
                if (path != null) await _setFloppy(1, path);
              },
              onClear: () => _setFloppy(1, null),
            ),
            SettingsSwitch(
              label: 'Accurate floppy timing',
              blurb: 'Off is fast and right for ordinary .st and .msa images. '
                  'On is needed by protected originals (.stx, .ipf) and makes '
                  'every load take as long as it did in 1988.',
              value: config.accurateFloppy,
              onChanged: (v) => onChanged(config.copyWith(accurateFloppy: v)),
            ),
          ],
        ),
        SettingsSection(
          title: 'Hard disk',
          blurb: 'Only one of these is used at a time. GEMDOS emulation is '
              'the easy one: point it at a folder and the ST sees the files '
              'as drive C, with no image to build.',
          children: [
            SettingsPath(
              label: 'GEMDOS folder',
              value: config.gemdosDir,
              emptyText: 'not fitted',
              onPick: () async {
                // Ask for the access first: the system picker will happily hand
                // back an SD-card path the app then cannot read.
                if (!await StoragePermission.ensure()) return;
                final dir = await FilePicker.platform.getDirectoryPath(
                    dialogTitle: 'Choose a folder to mount as drive C');
                if (dir != null) onChanged(config.copyWith(gemdosDir: dir));
              },
              onClear: () => onChanged(config.copyWith(gemdosDir: '')),
            ),
            SettingsPath(
              label: 'ACSI image',
              value: config.acsiImage,
              emptyText: 'not fitted',
              blurb: 'A real partitioned disk image, for software that will '
                  'not run under GEMDOS emulation.',
              onPick: () async {
                final path = await _pickFile('Choose an ACSI disk image');
                if (path != null) onChanged(config.copyWith(acsiImage: path));
              },
              onClear: () => onChanged(config.copyWith(acsiImage: '')),
            ),
            SettingsPath(
              label: 'IDE image',
              value: config.ideImage,
              emptyText: 'not fitted',
              onPick: () async {
                final path = await _pickFile('Choose an IDE disk image');
                if (path != null) onChanged(config.copyWith(ideImage: path));
              },
              onClear: () => onChanged(config.copyWith(ideImage: '')),
            ),
          ],
        ),
      ],
    );
  }
}
