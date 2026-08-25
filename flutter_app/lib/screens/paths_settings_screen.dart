// "Paths": where the app reads software from and writes its own files to.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/settings_controls.dart';

class PathsSettingsScreen extends StatelessWidget {
  final String gamesFolder;
  final String workDir;
  final String tosDir;
  final ValueChanged<String> onGamesFolderChanged;

  const PathsSettingsScreen({
    super.key,
    required this.gamesFolder,
    required this.workDir,
    required this.tosDir,
    required this.onGamesFolderChanged,
  });

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
            SettingsPath(
              label: 'Folder',
              value: gamesFolder,
              onPick: () async {
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
