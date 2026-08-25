// Colours and sizing shared with the rest of the Retro-* family, so the front
// ends read as siblings rather than unrelated apps.
//
// Every metric below is deliberately the same value the DOSBox, C64 and Saturn
// apps use. Only the accent differs per machine, and that is the point: the
// shape of the workbench is the family's, the colour is the hardware's.
import 'package:flutter/material.dart';

class RetroAtariStColors {
  RetroAtariStColors._();

  static const Color rootBackground = Color(0xFF050607);

  static const Color panelFill = Color(0xCC0B0D10);
  static const Color panelStroke = Color(0x44FFFFFF);

  static const Color selectedFill = Color(0xFF24292E);
  static const Color selectedStroke = Color(0xFF444D56);

  static const Color sidebarLabelIdle = Color(0xFF8C939D);
  static const Color sidebarLabelSelected = Colors.white;

  /// Atari's own red -- the Fuji logo, the ST's badge, the box art. The
  /// DOSBox app took amber from a monochrome PC monitor and the C64 app took
  /// its blue from the boot screen; this is the same idea, from the machine
  /// rather than from a palette.
  static const Color accentAtariRed = Color(0xFFE1141C);

  /// The GEM desktop's green. Used where the app is imitating TOS itself --
  /// the boot readout, the drive lights -- rather than its own chrome.
  static const Color accentDesktopGreen = Color(0xFF00A000);

  static const Color cardFill = Color(0xFF191D22);
  static const Color cardStroke = Color(0xFF353B44);
  static const Color coverFill = Color(0xFF262C34);
  static const Color coverStroke = Color(0xFF404853);

  static const Color textMuted = Color(0xFF9AA3AF);
  static const Color textMuted2 = Color(0xFFBAC2CC);

  static const Color warning = Color(0xFFE5A00D);
  static const Color danger = Color(0xFFE53935);
}

class RetroAtariStMetrics {
  RetroAtariStMetrics._();

  /// Clamp bounds for the sidebar, whose width is measured from its widest
  /// label rather than fixed.
  static const double sidebarMinWidth = 118.0;

  /// Never below [sidebarMinWidth], because this is a clamp's upper bound.
  ///
  /// A quarter of a narrow screen is less than the minimum - under about
  /// 472dp - and clamp(min, max) throws outright when max < min. That throws
  /// inside Sidebar.build, taking the whole workbench subtree with it: the
  /// symptom is a panel that never draws while the emulator runs perfectly,
  /// sound and all, because the failure is in the launcher's UI rather than
  /// anywhere near the emulator.
  /// Raised from the family's 190 to 210, and the 4px matter.
  ///
  /// The rail measures its widest label and then clamps to this. "Compliance"
  /// -- the longest destination any app in the family has -- measures 194 with
  /// the icon column and paddings, so a 190 cap clipped it to "Complian..." at
  /// EVERY window size, not just on narrow ones. It is visible in every
  /// sibling app for the same reason.
  ///
  /// Fixed here by raising the cap rather than by shortening the label: the
  /// tab is called Compliance in all of them on purpose, and the rail is
  /// supposed to size itself to its content.
  static const double sidebarMaxWidthCap = 210.0;

  static double sidebarMaxWidth(double screenWidth) {
    final quarter = screenWidth * 0.25;
    final capped =
        quarter < sidebarMaxWidthCap ? quarter : sidebarMaxWidthCap;
    return capped < sidebarMinWidth ? sidebarMinWidth : capped;
  }

  /// A floor, not a fixed height: the row grows with the platform text scale,
  /// which is what stops labels looking cramped on handheld devices that
  /// default to 1.35x.
  static const double sidebarButtonHeight = 36.0;
  static const double sidebarButtonTextSize = 13.0;
  static const double sidebarButtonBottomMargin = 4.0;
  static const double sidebarButtonSidePadding = 10.0;
  static const double sidebarButtonVerticalPadding = 8.0;

  static const double rootPadding = 12.0;
  static const double sideNavPadding = 6.0;
  static const double contentLeftMargin = 12.0;

  static const double mediaCardWidth = 120.0;
  static const double mediaCardHeight = 178.0;
  static const double mediaCoverHeight = 120.0;

  /// Card plus margins, for column math in the library grid.
  static const double mediaCardCell = 126.0;
}

/// Monospace styling for the places this app deliberately looks like the ST
/// itself -- the boot readout, status lines, config help text.
///
/// Applied per style, never as a global `fontFamily` on the MaterialApp theme:
/// the sidebar measures its own labels to size the rail, and a global override
/// renders text wider than the measurement, which clips labels ("Complian...").
class RetroAtariStTextStyles {
  RetroAtariStTextStyles._();

  static const TextStyle terminal = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier New', 'DejaVu Sans Mono'],
    fontSize: 13,
    height: 1.35,
    color: RetroAtariStColors.accentDesktopGreen,
  );

  static const TextStyle statusLine = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier New', 'DejaVu Sans Mono'],
    fontSize: 11,
    color: RetroAtariStColors.textMuted,
  );
}
