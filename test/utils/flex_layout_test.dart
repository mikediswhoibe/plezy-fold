import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/utils/flex_layout.dart';
import 'package:plezy/utils/fold_feature_service.dart';
import 'package:plezy/utils/hinge_posture_service.dart';

FoldFeature _foldable({
  FoldState state = FoldState.half,
  FoldOrientation orientation = FoldOrientation.horizontal,
  int left = 0,
  int top = 0,
  int right = 0,
  int bottom = 0,
}) {
  return FoldFeature.fromNative({
    'state': state == FoldState.half ? 'half' : 'flat',
    'orientation': orientation == FoldOrientation.vertical ? 'vertical' : 'horizontal',
    'bounds': [left, top, right, bottom],
  });
}

void main() {
  group('flexLayoutModeFor', () {
    test('is disabled when the setting is off', () {
      expect(flexLayoutModeFor(_foldable(), enabled: false), FlexLayoutMode.disabled);
    });

    test('is disabled for non-foldable windows', () {
      expect(flexLayoutModeFor(FoldFeature.none, enabled: true), FlexLayoutMode.disabled);
    });

    test('is disabled while flat', () {
      expect(flexLayoutModeFor(_foldable(state: FoldState.flat), enabled: true), FlexLayoutMode.disabled);
    });

    test('is tabletop for a half-opened horizontal hinge', () {
      expect(
        flexLayoutModeFor(_foldable(orientation: FoldOrientation.horizontal), enabled: true),
        FlexLayoutMode.tabletop,
      );
    });

    test('is book for a half-opened vertical hinge', () {
      expect(flexLayoutModeFor(_foldable(orientation: FoldOrientation.vertical), enabled: true), FlexLayoutMode.book);
    });

    test('forced preview feature selects tabletop when enabled', () {
      expect(flexLayoutModeFor(FoldFeature.previewTabletop, enabled: true), FlexLayoutMode.tabletop);
    });
  });

  group('flexLayoutSplit', () {
    test('is null when disabled', () {
      expect(
        flexLayoutSplit(FlexLayoutMode.disabled, FoldFeature.none, const Size(1000, 800), devicePixelRatio: 2),
        isNull,
      );
    });

    test('splits tabletop at the hinge center in logical pixels', () {
      // Hinge occupies device rows 1320..1400 (center 1360); at dpr 2 that
      // is 680 logical pixels.
      final feature = _foldable(left: 0, top: 1320, right: 2880, bottom: 1400);
      final split = flexLayoutSplit(FlexLayoutMode.tabletop, feature, const Size(1440, 1500), devicePixelRatio: 2);

      expect(split, isNotNull);
      expect(split!.mainAxis, Axis.vertical);
      expect(split.videoExtent, 680);
    });

    test('splits book at the hinge center X', () {
      final feature = _foldable(orientation: FoldOrientation.vertical, left: 1392, top: 0, right: 1488, bottom: 2224);
      final split = flexLayoutSplit(FlexLayoutMode.book, feature, const Size(1440, 2224), devicePixelRatio: 2.625);

      expect(split, isNotNull);
      expect(split!.mainAxis, Axis.horizontal);
      expect(split.videoExtent, (1392 + 1488) / 2 / 2.625);
    });

    test('falls back to the window middle for a hinge outside the window', () {
      final feature = _foldable(top: 4000, bottom: 4100);
      final split = flexLayoutSplit(FlexLayoutMode.tabletop, feature, const Size(1000, 800), devicePixelRatio: 1);

      expect(split!.videoExtent, 400);
    });

    test('falls back to the window middle for a zero-size hinge', () {
      final feature = _foldable();
      final split = flexLayoutSplit(FlexLayoutMode.tabletop, feature, const Size(1000, 800), devicePixelRatio: 1);

      expect(split!.videoExtent, 400);
    });

    test('forced preview feature splits at the window middle', () {
      // previewTabletop has zero hinge bounds, so the split must land exactly
      // at the middle of the 2000px-tall window: video 1000, panel 1000.
      final split = flexLayoutSplit(
        FlexLayoutMode.tabletop,
        FoldFeature.previewTabletop,
        const Size(1000, 2000),
        devicePixelRatio: 2,
      );

      expect(split, isNotNull);
      expect(split!.mainAxis, Axis.vertical);
      expect(split.videoExtent, 1000);
    });
  });

  group('flexDecisionFor', () {
    // The Z Fold 8 presentation: portrait window 657.07x870.4 (device px
    // 1848x2448 at dpr 2.8125); the tent hinge is the zero-height row at
    // device row 1224 spanning the 1848-wide display.
    const portraitWindow = Size(657.07, 870.4);
    const landscapeWindow = Size(870.4, 657.07);
    FoldFeature tent() => _foldable(state: FoldState.flat, left: 0, top: 1224, right: 1848, bottom: 1224);
    FoldFeature flatVertical() => _foldable(state: FoldState.flat, orientation: FoldOrientation.vertical);
    HingePosture bentPosture() => HingePosture.fromNative(const {'available': true, 'angle': 90.0, 'bent': true});
    HingePosture flatPosture() => HingePosture.fromNative(const {'available': true, 'angle': 180.0, 'bent': false});

    // -- Hinge-angle sensor: the authoritative posture signal, where present.

    test('sensor bent: the split is active (tabletop at the real hinge)', () {
      final decision = flexDecisionFor(tent(), window: portraitWindow, flexEnabled: false, force: true, posture: bentPosture());
      expect(decision.mode, FlexLayoutMode.tabletop);
      expect(decision.feature.hingeCenterY, 1224);
    });

    test('sensor flat: no split even in a portrait window (the flat-held-upright regression)', () {
      // A flat device held upright presents an identical portrait window with
      // a horizontal hinge to a tent; only the sensor tells them apart.
      final decision = flexDecisionFor(flatVertical(), window: portraitWindow, flexEnabled: true, force: false, posture: flatPosture());
      expect(decision.mode, FlexLayoutMode.disabled);
    });

    test('sensor bent: the auto path splits while the device is bent', () {
      final decision = flexDecisionFor(tent(), window: portraitWindow, flexEnabled: true, force: false, posture: bentPosture());
      expect(decision.mode, FlexLayoutMode.tabletop);
    });

    test('sensor flat: the auto path never splits', () {
      final decision = flexDecisionFor(tent(), window: portraitWindow, flexEnabled: true, force: false, posture: flatPosture());
      expect(decision.mode, FlexLayoutMode.disabled);
    });

    // -- Geometry fallback: devices without the hinge-angle sensor.

    test('fallback: the platform half-opened state classifies tabletop', () {
      final decision = flexDecisionFor(_foldable(), window: portraitWindow, flexEnabled: true, force: false);
      expect(decision.mode, FlexLayoutMode.tabletop);
    });

    test('fallback: the platform half-opened state classifies book for a vertical hinge', () {
      final decision = flexDecisionFor(_foldable(orientation: FoldOrientation.vertical), window: landscapeWindow, flexEnabled: true, force: false);
      expect(decision.mode, FlexLayoutMode.book);
    });

    test('fallback: a flat state with a live horizontal hinge in a portrait window splits (the tent presentation)', () {
      final decision = flexDecisionFor(tent(), window: portraitWindow, flexEnabled: true, force: false);
      expect(decision.mode, FlexLayoutMode.tabletop);
    });

    test('fallback: a horizontal hinge in a landscape window never splits (posture-transition transient)', () {
      final decision = flexDecisionFor(tent(), window: landscapeWindow, flexEnabled: true, force: false);
      expect(decision.mode, FlexLayoutMode.disabled);
    });

    test('fallback: a vertical hinge (flat display) never splits', () {
      final decision = flexDecisionFor(flatVertical(), window: portraitWindow, flexEnabled: true, force: false);
      expect(decision.mode, FlexLayoutMode.disabled);
    });

    // -- Force on a non-foldable, and enablement.

    test('force (non-foldable): a portrait window falls back to the preview feature (window middle)', () {
      final decision = flexDecisionFor(FoldFeature.none, window: portraitWindow, flexEnabled: false, force: true);
      expect(decision.mode, FlexLayoutMode.tabletop);
      expect(decision.feature, FoldFeature.previewTabletop);
    });

    test('force (non-foldable): a landscape window keeps the standard controls', () {
      final decision = flexDecisionFor(FoldFeature.none, window: landscapeWindow, flexEnabled: true, force: true);
      expect(decision.mode, FlexLayoutMode.disabled);
    });

    test('force acts as its own enable on a foldable (flex pref off, sensor bent)', () {
      final decision = flexDecisionFor(tent(), window: portraitWindow, flexEnabled: false, force: true, posture: bentPosture());
      expect(decision.mode, FlexLayoutMode.tabletop);
    });

    test('the flex pref off and no force disables every path, even when bent', () {
      final decision = flexDecisionFor(tent(), window: portraitWindow, flexEnabled: false, force: false, posture: bentPosture());
      expect(decision.mode, FlexLayoutMode.disabled);
    });
  });

  group('flexVideoRegion', () {
    test('is null without a split', () {
      expect(flexVideoRegion(null, const Size(800, 600), 2), isNull);
    });

    test('tabletop: the video owns the top extent rows at full width, in device pixels', () {
      // The Fold's portrait window: 1848x2448 device px at dpr 2.8125
      // (657.06 x 870.4 logical), split at the hinge center 435.2 logical.
      final split = const FlexLayoutSplit(mainAxis: Axis.vertical, videoExtent: 435.2);
      expect(
        flexVideoRegion(split, const Size(657.06, 870.4), 2.8125),
        (left: 0, top: 0, right: 1848, bottom: 1224),
      );
    });

    test('book: the video owns the left extent columns at full height', () {
      final split = const FlexLayoutSplit(mainAxis: Axis.horizontal, videoExtent: 400);
      expect(
        flexVideoRegion(split, const Size(1200, 800), 3),
        (left: 0, top: 0, right: 1200, bottom: 2400),
      );
    });

    test('rounds fractional extents outward', () {
      final split = const FlexLayoutSplit(mainAxis: Axis.vertical, videoExtent: 100.3);
      expect(
        flexVideoRegion(split, const Size(300, 500), 2),
        (left: 0, top: 0, right: 600, bottom: 201),
      );
    });
  });
}
