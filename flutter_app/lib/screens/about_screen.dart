import 'package:flutter/material.dart';

import '../theme/retro_atarist_theme.dart';
import '../widgets/settings_controls.dart';

class AboutScreen extends StatelessWidget {
  final String? appBuild;
  final String? coreVersion;
  final String? audioBackend;
  final bool usingStub;
  final VoidCallback? onRunSetupWizard;

  const AboutScreen({
    super.key,
    this.appBuild,
    this.coreVersion,
    this.audioBackend,
    this.usingStub = false,
    this.onRunSetupWizard,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SettingsSection(
          title: 'Retro-AtariST',
          blurb: 'An Atari ST front end for Android, iOS and Linux.',
          children: [
            _Row('App build', appBuild ?? 'unknown'),
            _Row('Emulator core',
                usingStub ? 'stub (no native core loaded)' : 'Hatari'),
            _Row('Core version', coreVersion ?? 'n/a'),
            _Row('Audio output',
                (audioBackend == null || audioBackend == 'none')
                    ? 'none -- this build has no audio sink'
                    : audioBackend!),
          ],
        ),
        SettingsSection(
          title: 'First run',
          children: [
            TextButton(
              onPressed: onRunSetupWizard,
              child: const Text('Show the setup information again'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    color: RetroAtariStColors.textMuted2, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: RetroAtariStTextStyles.statusLine),
          ),
        ],
      ),
    );
  }
}
