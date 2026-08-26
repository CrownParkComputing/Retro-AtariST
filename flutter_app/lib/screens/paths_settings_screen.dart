// "Paths": where the app reads software from and writes its own files to.
import '../services/storage_permission.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/settings_controls.dart';

class PathsSettingsScreen extends StatelessWidget {
  final String gamesFolder;
  final String workDir;
  final String tosDir;
  final ValueChanged<String> onGamesFolderChanged;

  /// The app-specific games folder on each storage volume. On a handheld
  /// that is usually built-in storage and a removable card; the card is
  /// preferred by default because an ST collection is hundreds of files and
  /// built-in storage is routinely the smaller of the two.
  final List<String> volumeChoices;

  const PathsSettingsScreen({
    super.key,
    required this.gamesFolder,
    required this.workDir,
    required this.tosDir,
    required this.onGamesFolderChanged,
    this.volumeChoices = const <String>[],
  });

  /// "Removable card" / "Built-in storage", from the path.
  ///
  /// Primary external storage lives under /storage/emulated; anything else is
  /// a card or a USB volume.
  static String _volumeLabel(String path) =>
      path.contains('/storage/emulated') ? 'Built-in storage' : 'Removable card';

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SettingsSection(
          title: 'Games folder',
          blurb: 'Scanned for disk images and for folders of ST programs. '
              'Loose .st/.msa/.stx/.ipf files become one entry each; disks of '
              'the same title ("Game (Disk 1)", "Game (Disk 2)") are grouped '
              'into one; a subfolder becomes a GEMDOS hard disk.',
          children: [
            if (volumeChoices.length > 1)
              SettingsDropdown<String>(
                label: 'Storage',
                value: volumeChoices.contains(gamesFolder)
                    ? gamesFolder
                    : volumeChoices.first,
                options: volumeChoices,
                labelOf: _volumeLabel,
                blurbOf: (path) => path,
                onChanged: onGamesFolderChanged,
              ),
            SettingsPath(
              label: 'Folder',
              value: gamesFolder,
              onPick: () async {
                // Ask for the access first: the system picker will happily hand
                // back an SD-card path the app then cannot read.
                if (!await StoragePermission.ensure()) return;
                final dir = await FilePicker.platform
                    .getDirectoryPath(dialogTitle: 'Choose the games folder');
                if (dir != null) onGamesFolderChanged(dir);
              },
            ),
          ],
        ),
        SettingsSection(
          title: 'App storage',
          blurb: 'Managed by the app. Shown so a save state or a config file '
              'can be found, backed up or deleted without guessing.',
          children: [
            SettingsPath(
              label: 'Core files',
              value: workDir,
              blurb: 'Hatari config, NVRAM and save states.',
            ),
            SettingsPath(
              label: 'TOS ROMs',
              value: tosDir,
            ),
          ],
        ),
      ],
    );
  }
}
