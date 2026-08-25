// The games list: search, an A-Z jump row, a kind filter, and a measured grid.
import 'package:flutter/material.dart';

import '../data/game_entry.dart';
import '../theme/retro_atarist_theme.dart';
import '../widgets/media_card.dart';

class LibraryGrid extends StatefulWidget {
  final List<GameEntry> entries;

  /// Paths that matched but could not be read. Reported in the status line
  /// because on Android this is what a scoped-storage permission problem
  /// looks like, and a quietly half-empty library is much harder to diagnose.
  final List<String> unreadable;

  final void Function(GameEntry entry) onLaunch;

  /// Library paths with a saved position. Marked on the card, because
  /// otherwise tapping one silently does something different from tapping
  /// its neighbour -- it resumes instead of starting.
  final Set<String> resumablePaths;

  /// Long-press action, for the per-title machine settings sheet.
  final void Function(GameEntry entry)? onShowDetails;

  final VoidCallback? onRescan;
  final VoidCallback? onAddGame;

  /// Shown instead of the grid when the library is empty, explaining where to
  /// put files. Null falls back to a generic message.
  final String? gamesFolderPath;

  const LibraryGrid({
    super.key,
    required this.entries,
    required this.onLaunch,
    this.resumablePaths = const <String>{},
    this.unreadable = const <String>[],
    this.onShowDetails,
    this.onRescan,
    this.onAddGame,
    this.gamesFolderPath,
  });

  @override
  State<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<LibraryGrid> {
  String _query = '';

  /// null means "All".
  GameKind? _kindFilter;

  /// null means "All letters".
  String? _letterFilter;

  List<GameEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    final letter = _letterFilter;
    return widget.entries.where((e) {
      if (_kindFilter != null && e.kind != _kindFilter) return false;
      if (letter != null) {
        final first = e.title.isEmpty ? '' : e.title[0].toLowerCase();
        // '#' is the catch-all bucket: digits and any other non-alphabetic
        // first character. A tile per digit would dominate the row in a
        // collection full of "1943", "007" and "3D Pool" without buying the
        // user any useful filtering.
        if (letter == '#') {
          final isAlpha = first.length == 1 &&
              first.codeUnitAt(0) >= 0x61 &&
              first.codeUnitAt(0) <= 0x7A;
          if (isAlpha) return false;
        } else if (first != letter) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  /// The letters actually used by the titles, so the jump row never offers a
  /// tile that leads nowhere.
  List<String> get _presentLetters {
    final hasAlpha = <String>{};
    var hasOther = false;
    for (final e in widget.entries) {
      if (e.title.isEmpty) continue;
      final c = e.title[0].toLowerCase();
      final code = c.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7A) {
        hasAlpha.add(c);
      } else {
        hasOther = true;
      }
    }
    const order = 'abcdefghijklmnopqrstuvwxyz';
    final result = <String>[];
    if (hasOther) result.add('#');
    for (final l in order.split('')) {
      if (hasAlpha.contains(l)) result.add(l);
    }
    return result;
  }

  List<GameKind> get _presentKinds {
    final kinds = <GameKind>{for (final e in widget.entries) e.kind};
    return GameKind.values.where(kinds.contains).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchRow(),
        const SizedBox(height: 8),
        if (_presentLetters.length > 1) _letterRow(),
        if (_presentKinds.length > 1) _kindRow(),
        _statusLine(filtered.length),
        const SizedBox(height: 4),
        Expanded(child: filtered.isEmpty ? _emptyState() : _grid(filtered)),
      ],
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search',
              hintStyle: const TextStyle(color: RetroAtariStColors.textMuted),
              prefixIcon: const Icon(Icons.search,
                  size: 18, color: RetroAtariStColors.textMuted),
              filled: true,
              fillColor: RetroAtariStColors.cardFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: RetroAtariStColors.cardStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: RetroAtariStColors.cardStroke),
              ),
            ),
          ),
        ),
        if (widget.onAddGame != null) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: widget.onAddGame,
            icon: const Icon(Icons.add, size: 20),
            color: RetroAtariStColors.textMuted2,
            tooltip: 'Add a disk image or folder',
          ),
        ],
        if (widget.onRescan != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onRescan,
            icon: const Icon(Icons.refresh, size: 20),
            color: RetroAtariStColors.textMuted2,
            tooltip: 'Rescan the games folder',
          ),
        ],
      ],
    );
  }

  Widget _letterRow() {
    final letters = <String?>[null, ..._presentLetters];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final letter in letters)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 8),
              child: _Chip(
                label: letter?.toUpperCase() ?? 'All',
                selected: _letterFilter == letter,
                onTap: () => setState(() => _letterFilter = letter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kindRow() {
    final kinds = <GameKind?>[null, ..._presentKinds];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final kind in kinds)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 8),
              child: _Chip(
                label: kind?.label ?? 'All',
                selected: _kindFilter == kind,
                onTap: () => setState(() => _kindFilter = kind),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusLine(int shown) {
    final total = widget.entries.length;
    final parts = <String>[
      shown == total ? '$total titles' : '$shown of $total titles',
      if (widget.unreadable.isNotEmpty)
        '${widget.unreadable.length} unreadable',
    ];
    return Text(parts.join('  |  '),
        style: RetroAtariStTextStyles.statusLine);
  }

  Widget _emptyState() {
    final folder = widget.gamesFolderPath;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No ST software found.',
                style: TextStyle(color: RetroAtariStColors.textMuted2)),
            const SizedBox(height: 8),
            Text(
              folder == null
                  ? 'Add disk images to the games folder, then rescan.'
                  : 'Put .st, .msa, .stx or .ipf disk images -- or a folder '
                      'of ST programs -- in:\n$folder',
              textAlign: TextAlign.center,
              style: RetroAtariStTextStyles.statusLine,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<GameEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured, not a fixed crossAxisCount: the same grid has to look
        // right on a phone in portrait and on a desktop window, and a fixed
        // count leaves either a single stretched column or a scrollbar.
        final columns =
            (constraints.maxWidth / RetroAtariStMetrics.mediaCardCell)
                .floor()
                .clamp(1, 16);
        return GridView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: RetroAtariStMetrics.mediaCardHeight,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return MediaCard(
              title: entry.title,
              kindLabel: entry.kind.badge,
              subtitle: entry.subtitle,
              resumable: widget.resumablePaths.contains(entry.path),
              onTap: () => widget.onLaunch(entry),
              onLongPress: widget.onShowDetails == null
                  ? null
                  : () => widget.onShowDetails!(entry),
            );
          },
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? RetroAtariStColors.selectedFill
                : RetroAtariStColors.cardFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? RetroAtariStColors.accentAtariRed
                  : RetroAtariStColors.cardStroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : RetroAtariStColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
