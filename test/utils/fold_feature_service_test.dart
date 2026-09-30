import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/utils/fold_feature_service.dart';

void main() {
  group('FoldFeature.fromNative', () {
    test('empty payloads report no fold feature', () {
      expect(FoldFeature.fromNative(const <String, Object>{}), FoldFeature.none);
    });

    test('non-map payloads report no fold feature', () {
      expect(FoldFeature.fromNative(null), FoldFeature.none);
      expect(FoldFeature.fromNative('garbage'), FoldFeature.none);
      expect(FoldFeature.fromNative(42), FoldFeature.none);
    });

    test('decodes a tabletop (half-opened, horizontal) feature', () {
      final feature = FoldFeature.fromNative({
        'state': 'half',
        'orientation': 'horizontal',
        'bounds': [0, 1320, 2880, 1400],
      });

      expect(feature.foldable, isTrue);
      expect(feature.state, FoldState.half);
      expect(feature.orientation, FoldOrientation.horizontal);
      expect(feature.boundsTop, 1320);
      expect(feature.boundsBottom, 1400);
      expect(feature.isTabletop, isTrue);
      expect(feature.isBook, isFalse);
      expect(feature.hingeCenterY, 1360);
    });

    test('decodes a book (half-opened, vertical) feature', () {
      final feature = FoldFeature.fromNative({
        'state': 'half',
        'orientation': 'vertical',
        'bounds': [1392, 0, 1488, 2224],
      });

      expect(feature.isBook, isTrue);
      expect(feature.isTabletop, isFalse);
      expect(feature.hingeCenterX, 1440);
    });

    test('a flat feature is not a split posture', () {
      final feature = FoldFeature.fromNative({
        'state': 'flat',
        'orientation': 'horizontal',
        'bounds': [0, 1360, 2880, 1400],
      });

      expect(feature.state, FoldState.flat);
      expect(feature.isTabletop, isFalse);
      expect(feature.isBook, isFalse);
    });

    test('missing bounds default to zero', () {
      final feature = FoldFeature.fromNative({'state': 'half', 'orientation': 'vertical'});

      expect(feature.foldable, isTrue);
      expect(feature.boundsLeft, 0);
      expect(feature.boundsBottom, 0);
    });

    test('values are equal by content', () {
      final a = FoldFeature.fromNative({
        'state': 'half',
        'orientation': 'horizontal',
        'bounds': [0, 1, 2, 3],
      });
      final b = FoldFeature.fromNative({
        'state': 'half',
        'orientation': 'horizontal',
        'bounds': [0, 1, 2, 3],
      });

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('FoldFeatureService', () {
    test('setForTesting notifies listeners only on change', () {
      final service = FoldFeatureService.instance;
      var notifications = 0;
      void listener() => notifications++;

      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));
      addTearDown(() => service.setForTesting(FoldFeature.none));

      service.setForTesting(FoldFeature.none);
      expect(notifications, 0);

      final feature = FoldFeature.fromNative({
        'state': 'half',
        'orientation': 'horizontal',
        'bounds': [0, 1, 2, 3],
      });
      service.setForTesting(feature);
      expect(service.current, feature);
      expect(notifications, 1);

      service.setForTesting(feature);
      expect(notifications, 1);
    });
  });
}
