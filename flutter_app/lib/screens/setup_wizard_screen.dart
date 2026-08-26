// First-run setup, the Retro-Amiga way: a phased walkthrough. Welcome (what
// did I just open), two teaching pages (what an ST needs, where files can
// live on THIS platform -- including the All-files-access story on Android),
// then the three-step form with the TOS picker.
//
// Shown once per numbered build, not once per installation -- app upgrades
// preserve preferences, and a lone "seen it" boolean would stop testers and
// store reviewers ever seeing revised information again.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/storage_permission.dart';
import '../theme/retro_atarist_theme.dart';
import 'getting_started.dart';

class SetupWizardScreen extends StatefulWidget {
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
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

/// The family's phased shape, from Retro-Amiga: introduce, teach, then ask.
enum _Phase { welcome, primer, form }

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  /// A TOS already chosen means this is a re-run (new build) rather than a
  /// first meeting -- skip straight to the form.
  late _Phase _phase = (widget.tosPath?.isNotEmpty ?? false)
      ? _Phase.form
      : _Phase.welcome;

  String? _notice;

  Future<void> _pickTos() async {
    // The ROM is read in place, so the pick needs the same access the
    // emulator will -- and the system picker will happily hand back an
    // SD-card path the app then cannot read.
    if (!await StoragePermission.ensure()) {
      if (!mounted) return;
      setState(
        () => _notice =
            'Without "All files access" the app cannot read a TOS ROM or '
            'games from an SD card. Grant it and try again.',
      );
      return;
    }
    setState(() => _notice = null);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a TOS ROM image',
    );
    final path = result?.files.single.path;
    if (path != null) widget.onTosChosen(path);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: switch (_phase) {
        _Phase.welcome => _welcomeView(context),
        _Phase.primer => _primerView(),
        _Phase.form => _formView(context),
      },
    );
  }

  Widget _welcomeView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  height: 104,
                  width: 104,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (BuildContext c, Object e, StackTrace? st) =>
                      const Icon(Icons.computer, size: 72),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Retro-AtariST',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Atari ST, Mega ST and STE, via Hatari.',
              textAlign: TextAlign.center,
              style: RetroAtariStTextStyles.statusLine,
            ),
            const SizedBox(height: 12),
            const Text(
              'An Atari ST, running on this device. Setup takes a couple of '
              'minutes: point the app at your TOS ROM and your disks and it '
              'reads them where they are.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RetroAtariStColors.accentAtariRed,
              ),
              onPressed: () => setState(() => _phase = _Phase.primer),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Get started'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _phase = _Phase.form),
              child: const Text('I have done this before'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primerView() {
    return GettingStartedGuide(
      steps: <GuideStep>[
        GettingStartedSteps.whatYouNeed(),
        GettingStartedSteps.whereFilesGo(),
      ],
      closeLabel: 'Set up my ST',
      onClose: () => setState(() => _phase = _Phase.form),
      onBack: () => setState(() => _phase = _Phase.welcome),
    );
  }

  Widget _formView(BuildContext context) {
    final tosPath = widget.tosPath;
    final hasTos = tosPath != null && tosPath.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _notice!,
                style: const TextStyle(color: Colors.orangeAccent, height: 1.4),
              ),
            ),
          const _Step(
            number: 1,
            title: 'A TOS ROM is required',
            body:
                'The ST has its operating system in ROM, and nothing '
                'boots without it. TOS is copyrighted by Atari, so this app '
                'does not include one -- you supply your own image, the '
                'same as the KERNAL in the C64 app.',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () => unawaited(_pickTos()),
                  child: Text(hasTos ? 'Change TOS ROM' : 'Choose TOS ROM'),
                ),
                const SizedBox(width: 12),
                if (hasTos)
                  const Icon(
                    Icons.check,
                    size: 18,
                    color: RetroAtariStColors.accentDesktopGreen,
                  ),
              ],
            ),
          ),
          _Step(
            number: 2,
            title: 'Put your software in the games folder',
            body:
                'Disk images (.st, .msa, .dim, .stx, .ipf) and folders of '
                'ST programs both work. Disks belonging to one title are '
                'grouped automatically.\n\n${widget.gamesFolder}',
          ),
          const _Step(
            number: 3,
            title: 'Pick a machine per title if you need to',
            body:
                'The default is a 1MB plain ST, which is what most games '
                'expect. Long-press a title to give it its own machine, '
                'memory size or floppy timing.',
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: widget.onComplete,
              style: FilledButton.styleFrom(
                backgroundColor: RetroAtariStColors.accentAtariRed,
              ),
              // Deliberately not disabled without a TOS ROM: someone may
              // want to look round the app before finding their ROM, and a
              // wizard that traps them on step 1 is worse than a library
              // that says why nothing launches.
              child: Text(hasTos ? 'Start' : 'Skip for now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String body;

  const _Step({required this.number, required this.title, required this.body});

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
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: RetroAtariStColors.textMuted2,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
