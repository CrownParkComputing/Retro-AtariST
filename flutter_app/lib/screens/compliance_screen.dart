// The offline, reviewer-facing evidence page, plus the compliance-mode switch.
//
// Every app in the Retro-* family has one of these, with the same name and the
// same vocabulary. It exists because an emulator front end submitted to an app
// store raises the same three questions every time -- what is emulated, whose
// code is it, and what can the app run out of the box -- and answering them
// inside the app, offline, is far more useful to a reviewer than a support
// email thread.
import 'package:flutter/material.dart';

import '../theme/retro_atarist_theme.dart';
import '../widgets/settings_controls.dart';

class ComplianceScreen extends StatelessWidget {
  final bool complianceMode;
  final ValueChanged<bool> onComplianceModeChanged;

  /// Hatari's version as the loaded core reports it, or null when running on
  /// the stub. Read from the core rather than hardcoded so this page cannot
  /// claim a version the binary does not have.
  final String? coreVersion;

  const ComplianceScreen({
    super.key,
    required this.complianceMode,
    required this.onComplianceModeChanged,
    this.coreVersion,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SettingsSection(
          title: 'Compliance mode',
          blurb: 'For store review and for demonstrations. With it on, the '
              'app offers only the bundled demonstration software and does '
              'not scan your library at all.',
          children: [
            SettingsSwitch(
              label: 'Bundled software only',
              value: complianceMode,
              onChanged: onComplianceModeChanged,
            ),
          ],
        ),
        const _Evidence(
          title: 'What this app is',
          body: 'Retro-AtariST is a front end for the Hatari emulator. It '
              'emulates the Atari ST, Mega ST, STE, Mega STE, TT and Falcon '
              'home computers, which Atari discontinued in 1993.',
        ),
        _Evidence(
          title: 'Emulator core',
          body: 'Hatari${coreVersion == null ? "" : " $coreVersion"}, by the '
              'Hatari team, under the GNU General Public Licence version 2 '
              'or later. Source: https://github.com/hatari/hatari\n\n'
              'This app vendors Hatari unmodified as a git submodule and adds '
              'its own UI backend alongside Hatari\'s SDL one. No Hatari '
              'source file is patched.',
        ),
        const _Evidence(
          title: 'ROMs and copyrighted material',
          body: 'No TOS ROM is included. TOS is copyrighted by Atari and must '
              'be supplied by the user, exactly as the KERNAL is in the C64 '
              'app in this family.\n\n'
              'No commercial game is included. The app plays disk images the '
              'user already has on their own device; it does not download, '
              'link to, or help locate any.',
        ),
        const _Evidence(
          title: 'Network use',
          body: 'The emulator does not use the network. The app makes no '
              'network request to run a title.',
        ),
        const _Evidence(
          title: 'Licence of this app',
          body: 'Because it links Hatari, this app is distributed under the '
              'GNU General Public Licence version 2 or later. The full text '
              'ships with the app and the source is public.',
        ),
      ],
    );
  }
}

class _Evidence extends StatelessWidget {
  final String title;
  final String body;

  const _Evidence({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RetroAtariStColors.cardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RetroAtariStColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  color: RetroAtariStColors.textMuted2,
                  fontSize: 12,
                  height: 1.4)),
        ],
      ),
    );
  }
}
