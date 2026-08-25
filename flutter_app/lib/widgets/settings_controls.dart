// The handful of controls every settings tab is built from.
//
// Extracted because four tabs otherwise repeat the same section header, the
// same labelled dropdown and the same file-picker row with slightly different
// padding each time -- and "slightly different" is exactly what makes a
// settings screen look unfinished.
import 'package:flutter/material.dart';

import '../theme/retro_atarist_theme.dart';

class SettingsSection extends StatelessWidget {
  final String title;
  final String? blurb;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.blurb,
  });

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (blurb != null) ...[
            const SizedBox(height: 4),
            Text(blurb!, style: RetroAtariStTextStyles.statusLine),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class SettingsDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final String? Function(T)? blurbOf;
  final ValueChanged<T> onChanged;

  const SettingsDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.blurbOf,
  });

  @override
  Widget build(BuildContext context) {
    final blurb = blurbOf?.call(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(label,
                    style: const TextStyle(
                        color: RetroAtariStColors.textMuted2, fontSize: 12)),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    value: value,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: RetroAtariStColors.cardFill,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    onChanged: (v) {
                      if (v != null) onChanged(v);
                    },
                    items: [
                      for (final option in options)
                        DropdownMenuItem<T>(
                          value: option,
                          child: Text(labelOf(option)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // The explanation sits under the control and follows the SELECTED
          // value, rather than being a static line of help: the difference
          // between an ST and an STE only matters at the moment you are
          // choosing between them.
          if (blurb != null && blurb.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 120, top: 2),
              child: Text(blurb, style: RetroAtariStTextStyles.statusLine),
            ),
        ],
      ),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  final String label;
  final String? blurb;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.blurb,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      activeThumbColor: RetroAtariStColors.accentAtariRed,
      title: Text(label,
          style: const TextStyle(
              color: RetroAtariStColors.textMuted2, fontSize: 12)),
      subtitle: blurb == null
          ? null
          : Text(blurb!, style: RetroAtariStTextStyles.statusLine),
    );
  }
}

/// A path with a "choose" button and a "clear" button.
///
/// [value] is shown in full rather than as a basename: two disk images called
/// "disk1.st" in different folders are a real and common situation, and a row
/// that shows only the filename cannot be used to tell them apart.
class SettingsPath extends StatelessWidget {
  final String label;
  final String? value;
  final String emptyText;
  final String? blurb;
  /// Null makes the row read-only -- no picker button at all, rather
  /// than a button that does nothing when pressed.
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  const SettingsPath({
    super.key,
    required this.label,
    required this.value,
    this.onPick,
    this.emptyText = 'not set',
    this.blurb,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final set = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label,
                      style: const TextStyle(
                          color: RetroAtariStColors.textMuted2, fontSize: 12)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    set ? value! : emptyText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: set
                          ? RetroAtariStColors.accentDesktopGreen
                          : RetroAtariStColors.textMuted,
                    ),
                  ),
                ),
              ),
              if (onPick != null)
                IconButton(
                  onPressed: onPick,
                  icon: const Icon(Icons.folder_open, size: 18),
                  color: RetroAtariStColors.textMuted2,
                  tooltip: 'Choose',
                ),
              if (set && onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18),
                  color: RetroAtariStColors.textMuted2,
                  tooltip: 'Clear',
                ),
            ],
          ),
          if (blurb != null)
            Padding(
              padding: const EdgeInsets.only(left: 120),
              child: Text(blurb!, style: RetroAtariStTextStyles.statusLine),
            ),
        ],
      ),
    );
  }
}
