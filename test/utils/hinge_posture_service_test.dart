import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/utils/hinge_posture_service.dart';

void main() {
  group('HingePosture.fromNative', () {
    test('empty or non-map payloads report an unavailable posture', () {
      expect(HingePosture.fromNative(const <String, Object>{}), HingePosture.none);
      expect(HingePosture.fromNative(null), HingePosture.none);
      expect(HingePosture.fromNative('garbage'), HingePosture.none);
    });

    test('a missing available flag reports an unavailable posture', () {
      expect(HingePosture.fromNative(const {'angle': 90.0, 'bent': true}), HingePosture.none);
    });

    test('decodes an available, bent posture', () {
      final posture = HingePosture.fromNative(const {'available': true, 'angle': 90.0, 'bent': true});

      expect(posture.available, isTrue);
      expect(posture.angleDegrees, 90.0);
      expect(posture.bent, isTrue);
    });

    test('decodes an available, flat posture', () {
      final posture = HingePosture.fromNative(const {'available': true, 'angle': 180.0, 'bent': false});

      expect(posture.available, isTrue);
      expect(posture.angleDegrees, 180.0);
      expect(posture.bent, isFalse);
    });

    test('values are equal by content', () {
      final a = HingePosture.fromNative(const {'available': true, 'angle': 90.0, 'bent': true});
      final b = HingePosture.fromNative(const {'available': true, 'angle': 90.0, 'bent': true});

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('HingePostureService', () {
    test('setForTesting notifies listeners only on change', () {
      final service = HingePostureService.instance;
      var notifications = 0;
      void listener() => notifications++;

      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));
      addTearDown(() => service.setForTesting(HingePosture.none));

      service.setForTesting(HingePosture.none);
      expect(notifications, 0);

      final posture = HingePosture.fromNative(const {'available': true, 'angle': 90.0, 'bent': true});
      service.setForTesting(posture);
      expect(service.current, posture);
      expect(notifications, 1);

      service.setForTesting(posture);
      expect(notifications, 1);
    });
  });
}