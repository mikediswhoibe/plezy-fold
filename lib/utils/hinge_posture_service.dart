import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fold_log.dart';

/// A snapshot of the device's physical hinge posture, read from the hinge
/// angle sensor (Android `Sensor.TYPE_HINGE_ANGLE`, API 30+).
///
/// [none] is reported on every non-Android platform, on devices without a
/// hinge-angle sensor, and on Android below API 30. In all of those cases
/// [available] is false and callers must fall back to window geometry.
class HingePosture {
  const HingePosture._({
    required this.available,
    this.angleDegrees,
    required this.bent,
  });

  static const HingePosture none = HingePosture._(available: false, bent: false);

  factory HingePosture.fromNative(dynamic raw) {
    if (raw is! Map || raw.isEmpty || raw['available'] != true) return HingePosture.none;
    return HingePosture._(
      available: true,
      angleDegrees: (raw['angle'] as num?)?.toDouble(),
      bent: raw['bent'] == true,
    );
  }

  /// Whether the device exposes a hinge-angle sensor.
  final bool available;

  /// The physical hinge angle in degrees, or null when [available] is false.
  final double? angleDegrees;

  /// Whether the hinge is in a half-opened (bent) posture — a mid-range angle
  /// (tent, book, any partial fold) — as opposed to flat or closed, which sit
  /// at the extremes. This is the signal that distinguishes "flat held
  /// upright" from "tent", which window geometry alone cannot.
  final bool bent;

  @override
  bool operator ==(Object other) =>
      other is HingePosture &&
      other.available == available &&
      other.angleDegrees == angleDegrees &&
      other.bent == bent;

  @override
  int get hashCode => Object.hash(available, angleDegrees, bent);

  @override
  String toString() => 'HingePosture(available: $available, angle: $angleDegrees, bent: $bent)';
}

/// Watches the native hinge-posture stream and exposes the current posture to
/// the rest of the app.
///
/// The native side ([HingeAngleMonitor]) pushes only on posture *transitions*
/// (the bent classification flips) and replays the last state to listeners
/// that attach late, so the current posture is available as soon as [init]
/// has run. [init] is idempotent and a no-op on every platform other than
/// Android, where the channel stays silent and [current] remains [HingePosture.none].
class HingePostureService extends ChangeNotifier {
  HingePostureService._();

  static final HingePostureService instance = HingePostureService._();

  static const EventChannel _channel = EventChannel('com.plezy/hinge_posture');

  HingePosture _current = HingePosture.none;
  HingePosture get current => _current;

  StreamSubscription<dynamic>? _subscription;

  /// Starts watching the native channel. Call once at startup.
  void init() {
    if (_subscription != null || !Platform.isAndroid) return;
    foldLog('hinge: service listening');
    _subscription = _channel.receiveBroadcastStream().listen((raw) {
      final next = HingePosture.fromNative(raw);
      final repeat = next == _current;
      foldLog('hinge: payload raw=$raw -> $next${repeat ? ' (repeat)' : ''}');
      if (repeat) return;
      _current = next;
      notifyListeners();
    });
  }

  /// Test seam: sets the reported posture without the native channel.
  @visibleForTesting
  void setForTesting(HingePosture next) {
    if (next == _current) return;
    _current = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}