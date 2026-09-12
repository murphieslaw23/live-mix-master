/// Composition-only tokens for the approved Picsart web reference layouts.
///
/// Semantic color/typography/interaction values remain owned by
/// `design/tokens.json` and `LiveMixTokens`. This file deliberately contains
/// only web composition geometry and repository asset paths.
abstract final class WebReferenceTokens {
  static const double compactBreakpoint = 680;
  static const double desktopRailWidth = 88;
  static const double operatorDrawerMaxWidth = 720;
  static const double panelGap = 12;
  static const double panelBorder = 1;
  static const int meterSegmentCount = 24;
  static const double meterSegmentGap = 3;

  static const String totemAsset = 'assets/brand/livemixmaster-totem.svg';
  static const String compactTotemAsset =
      'assets/brand/livemixmaster-totem-compact.svg';
  static const String inverseTotemAsset =
      'assets/brand/livemixmaster-totem-inverse.svg';
  static const String pwaMaskableAsset =
      'web/icons/livemixmaster-maskable.svg';
}
