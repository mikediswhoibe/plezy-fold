import 'package:flutter/widgets.dart';

import 'fold_feature_service.dart';
import 'hinge_posture_service.dart';

/// Which split (if any) the player screen should use on this frame.
enum FlexLayoutMode { disabled, tabletop, book }

/// A computed split of the player screen for flex layout: the video surface
/// occupies the region before the split line, the compact controls panel the
/// remainder.
class FlexLayoutSplit {
  const FlexLayoutSplit({required this.mainAxis, required this.videoExtent});

  /// [Axis.vertical] = column layout (tabletop: video top, controls bottom);
  /// [Axis.horizontal] = row layout (book: video left, controls right).
  final Axis mainAxis;

  /// Size of the video region along [mainAxis], in logical pixels.
  final double videoExtent;

  @override
  bool operator ==(Object other) =>
      other is FlexLayoutSplit && other.mainAxis == mainAxis && other.videoExtent == videoExtent;

  @override
  int get hashCode => Object.hash(mainAxis, videoExtent);

  @override
  String toString() => 'FlexLayoutSplit(mainAxis: $mainAxis, videoExtent: $videoExtent)';
}

/// Chooses the flex layout mode for the current window fold [feature] and the
/// user's [enabled] preference.
FlexLayoutMode flexLayoutModeFor(FoldFeature feature, {required bool enabled}) {
  if (!enabled || !feature.foldable) return FlexLayoutMode.disabled;
  if (feature.isTabletop) return FlexLayoutMode.tabletop;
  if (feature.isBook) return FlexLayoutMode.book;
  return FlexLayoutMode.disabled;
}

/// The full flex decision for one frame: the [FlexLayoutMode] to use and the
/// [FoldFeature] whose hinge bounds the split is computed from.
///
/// Three paths, in priority order:
///
/// 1. **Force on a non-foldable** ([force] = the "force compact controls"
///    setting, and the window is not foldable): no fold state exists, so the
///    setting falls back to the orientation-keyed preview — a portrait window
///    (taller than wide) gets the tabletop split at the window's middle
///    ([FoldFeature.previewTabletop]); a landscape window keeps the standard
///    controls.
///
/// 2. **The hinge-angle posture** ([posture], available when the device
///    exposes `Sensor.TYPE_HINGE_ANGLE`): the authoritative signal. A bent
///    (half-opened) posture selects the tabletop split; a flat or closed
///    posture selects no split. This is what distinguishes "flat, held
///    upright" from "tent" — two cases that present an identical portrait
///    window with a horizontal hinge and that window geometry cannot tell
///    apart. On this path the split is shown only while the device is
///    actually bent.
///
/// 3. **The geometry fallback** (no hinge-angle sensor): where the platform
///    reports the half-opened windowing state ([FoldState.half]) the standard
///    classification applies (horizontal hinge → tabletop, vertical → book);
///    on a single-window presentation the state stays [FoldState.flat], so a
///    horizontal hinge on a portrait window (the tent presentation) selects
///    the tabletop split.
///
/// Paths 2 and 3 are gated by [flexEnabled] (the "fold split layout"
/// preference); [force] acts as its own enable on a foldable. The split is
/// applied live in both directions as the posture transitions.
({FlexLayoutMode mode, FoldFeature feature}) flexDecisionFor(
  FoldFeature fold, {
  required Size window,
  required bool flexEnabled,
  required bool force,
  HingePosture posture = HingePosture.none,
}) {
  final isPortrait = window.height > window.width;
  if (force && !fold.foldable) {
    return isPortrait
        ? (mode: FlexLayoutMode.tabletop, feature: FoldFeature.previewTabletop)
        : (mode: FlexLayoutMode.disabled, feature: fold);
  }
  if (!force && !flexEnabled) return (mode: FlexLayoutMode.disabled, feature: fold);
  if (!fold.foldable) return (mode: FlexLayoutMode.disabled, feature: fold);

  // The hinge-angle sensor is the authoritative posture source where present.
  if (posture.available) {
    if (posture.bent) return (mode: FlexLayoutMode.tabletop, feature: fold);
    return (mode: FlexLayoutMode.disabled, feature: fold);
  }

  // No sensor: fall back to the platform half-opened state, then the live
  // hinge geometry.
  if (fold.state == FoldState.half) {
    return (mode: flexLayoutModeFor(fold, enabled: true), feature: fold);
  }
  if (fold.orientation == FoldOrientation.horizontal && isPortrait) {
    return (mode: FlexLayoutMode.tabletop, feature: fold);
  }
  return (mode: FlexLayoutMode.disabled, feature: fold);
}

/// Computes the split for [mode] across a [window] of logical-pixel size.
///
/// The native hinge bounds are device-pixel coordinates on the (bent)
/// display; dividing by [devicePixelRatio] yields logical pixels. Returns
/// null for [FlexLayoutMode.disabled]. A degenerate hinge position (outside
/// the window, e.g. synthetic window info) falls back to the window's middle
/// instead of producing a zero-size region.
FlexLayoutSplit? flexLayoutSplit(
  FlexLayoutMode mode,
  FoldFeature feature,
  Size window, {
  required double devicePixelRatio,
}) {
  final extent = switch (mode) {
    FlexLayoutMode.disabled => null,
    FlexLayoutMode.tabletop => feature.hingeCenterY / devicePixelRatio,
    FlexLayoutMode.book => feature.hingeCenterX / devicePixelRatio,
  };
  if (extent == null) return null;

  final axis = mode == FlexLayoutMode.tabletop ? Axis.vertical : Axis.horizontal;
  final limit = axis == Axis.vertical ? window.height : window.width;
  var clamped = extent.clamp(0.0, limit);
  if (clamped <= 0 || clamped >= limit) {
    // The hinge is not actually inside this window; split it in half.
    clamped = limit / 2;
  }
  return FlexLayoutSplit(mainAxis: axis, videoExtent: clamped);
}

/// Device-pixel rectangle (content-view coordinates, top-left origin) that the
/// native video surface occupies while [FlexLayoutSplit] is active.
///
/// The split layout anchors the video area at the screen's top-left corner
/// (Column: video above the panel; Row: video left of it), so the region is
/// always `left=0, top=0`. Bounds round outward, the same way the native side
/// biases: a fractional extent must never leave a physical-pixel seam between
/// the surface and the Flutter panel.
typedef FlexVideoRegion = ({int left, int top, int right, int bottom});

/// The device-pixel video-surface region for [split], or null when the
/// surface should fill the window (no split).
FlexVideoRegion? flexVideoRegion(FlexLayoutSplit? split, Size window, double devicePixelRatio) {
  if (split == null) return null;
  if (split.mainAxis == Axis.vertical) {
    // Tabletop: the video owns the top [FlexLayoutSplit.videoExtent] rows, full width.
    return (
      left: 0,
      top: 0,
      right: (window.width * devicePixelRatio).ceil(),
      bottom: (split.videoExtent * devicePixelRatio).ceil(),
    );
  }
  // Book: the video owns the left [FlexLayoutSplit.videoExtent] columns, full height.
  return (
    left: 0,
    top: 0,
    right: (split.videoExtent * devicePixelRatio).ceil(),
    bottom: (window.height * devicePixelRatio).ceil(),
  );
}
