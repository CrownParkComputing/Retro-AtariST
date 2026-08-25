import 'sidebar.dart';
import '../theme/retro_atarist_theme.dart';

/// The Atari ST front end's rail palette. This adapter is the only per-app
/// part of the side nav -- widgets/sidebar.dart itself is identical in every
/// Retro-* app, so a fix there lands everywhere instead of once.
const SidebarStyle retroAtariStSidebarStyle = SidebarStyle(
  panelFill: RetroAtariStColors.panelFill,
  panelStroke: RetroAtariStColors.panelStroke,
  selectedFill: RetroAtariStColors.selectedFill,
  selectedStroke: RetroAtariStColors.selectedStroke,
  labelIdle: RetroAtariStColors.sidebarLabelIdle,
  labelSelected: RetroAtariStColors.sidebarLabelSelected,
  minWidth: RetroAtariStMetrics.sidebarMinWidth,
  buttonHeight: RetroAtariStMetrics.sidebarButtonHeight,
  buttonTextSize: RetroAtariStMetrics.sidebarButtonTextSize,
  buttonBottomMargin: RetroAtariStMetrics.sidebarButtonBottomMargin,
  buttonSidePadding: RetroAtariStMetrics.sidebarButtonSidePadding,
  buttonVerticalPadding: RetroAtariStMetrics.sidebarButtonVerticalPadding,
  navPadding: RetroAtariStMetrics.sideNavPadding,
  maxWidth: RetroAtariStMetrics.sidebarMaxWidth,
);
