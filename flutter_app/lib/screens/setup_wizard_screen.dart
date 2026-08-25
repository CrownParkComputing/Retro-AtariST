// First run: the three things someone has to know before anything will boot.
//
// Shown once per numbered build, not once per installation -- app upgrades
// preserve preferences, and a lone "seen it" boolean would stop testers and
// store reviewers ever seeing revised information again.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/retro_atarist_theme.dart';

class SetupWizardScreen extends StatelessWidget {
  final String? appBuild;
  final String? tosPath;
  final String gamesFolder;
  final ValueChanged<String> onTosChosen;
  final VoidCallback onComplete;

  const SetupWizardScreen({
    super.key,
    required this.gamesFolder,
    required this.onTosChosen,
    required this.onComplete,
    this.appBuild,
    this.tosPath,
  });

  @override
  Widget build(BuildContext context) {
    final hasTos = tosPath != null && tosPath!.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const Text(
              'Retro-AtariST',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('Atari ST, Mega ST and STE, via Hatari.',
                style: RetroAtariStTextStyles.statusLine),
            const SizedBox(height: 24),
            const _Step(
              number: 1,
              title: 'A TOS ROM is required',
              body: 'The ST has its operating system in ROM, and nothing '
                  'boots without it. TOS is copyrighted by Atari, so this app '
                  'does not include one -- you supply your own image, the '
                  'same as the KERNAL in the C64 app.',
            ),
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 16),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                          dialogTitle: 'Choose a TOS ROM image');
                      final path = result?.files.single.path;
                      if (path != null) onTosChosen(path);
                    },
                    child: Text(hasTos ? 'Change TOS ROM' : 'Choose TOS ROM'),
                  ),
                  const SizedBox(width: 12),
                  if (hasTos)
                    const Icon(Icons.check,
                        size: 18, color: RetroAtariStColors.accentDesktopGreen),
                ],
              ),
            ),
            _Step(
              number: 2,
              title: 'Put your software in the games folder',
              body: 'Disk images (.st, .msa, .dim, .stx, .ipf) and folders of '
                  'ST programs both work. Disks belonging to one title are '
                  'grouped automatically.\n\n$gamesFolder',
            ),
            const _Step(
              number: 3,
              title: 'Pick a machine per title if you need to',
              body: 'The default is a 1MB plain ST, which is what most games '
                  'expect. Long-press a title to give it its own machine, '
                  'memory size or floppy timing.',
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onComplete,
                style: FilledButton.styleFrom(
                    backgroundColor: RetroAtariStColors.accentAtariRed),
                // Deliberately not disabled without a TOS ROM: someone may
                // want to look round the app before finding their ROM, and a
                // wizard that traps them on step 1 is worse than a library
                // that says why nothing launches.
                child: Text(hasTos ? 'Start' : 'Skip for now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String body;

  const _Step({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: RetroAtariStColors.accentAtariRed,
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: RetroAtariStColors.textMuted2,
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
