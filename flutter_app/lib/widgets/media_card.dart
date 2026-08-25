import 'package:flutter/material.dart';

import '../theme/retro_atarist_theme.dart';

/// One title in the library grid.
///
/// Takes plain strings, not a GameEntry: the card draws exactly what it is
/// given and cannot break when the data layer changes shape. Box art is
/// deferred; the cover slot shows [kindLabel], the same fallback the sibling
/// apps use while art has not loaded.
class MediaCard extends StatelessWidget {
  /// Display name, e.g. "Dungeon Master". Wraps to two lines, then
  /// ellipsises.
  final String title;

  /// Very short description of what the entry is -- "FD", "HD", "ZIP".
  /// Drawn large in the cover slot, so keep it to a few characters.
  final String kindLabel;

  /// Optional second line under the title: a disk count, a format. Omitted
  /// entirely when null, so the card does not reserve a blank strip for
  /// entries with nothing to say.
  final String? subtitle;

  /// True when this title has a saved position, so tapping resumes rather
  /// than starts. Marked because two cards that look identical should not
  /// behave differently.
  final bool resumable;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const MediaCard({
    super.key,
    required this.title,
    required this.kindLabel,
    required this.onTap,
    this.subtitle,
    this.onLongPress,
    this.resumable = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: RetroAtariStMetrics.mediaCardWidth,
      height: RetroAtariStMetrics.mediaCardHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: RetroAtariStColors.cardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: RetroAtariStColors.cardStroke),
            ),
            child: Column(
              children: [
                Container(
                  height: RetroAtariStMetrics.mediaCoverHeight,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: RetroAtariStColors.coverFill,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: RetroAtariStColors.coverStroke),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        kindLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB9C2CE),
                          fontSize: 12,
                        ),
                      ),
                      if (resumable)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: RetroAtariStColors.accentAtariRed,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow,
                                    size: 9, color: Colors.white),
                                SizedBox(width: 2),
                                Text('RESUME',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 7,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
                if (subtitle != null)
                  SizedBox(
                    height: 16,
                    child: Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: RetroAtariStColors.textMuted, fontSize: 8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
