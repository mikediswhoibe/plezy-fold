import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fold_log.dart';

/// The fold state of the app window, as reported by
/// [androidx.window.layout.FoldingFeature] on Android.
enum FoldState { flat, half }

/// Hinge orientation of a foldable display.
enum FoldOrientation { horizontal, vertical }

/// A snapshot of the app window's fold feature, in device-pixel space.
///
/// [none] is reported on every non-foldable device, on non-Android platforms,
/// and on Android below API 29 (the first foldable shipped on Android 10).
class FoldFeature {
  const FoldFeature._({
    required this.foldable,
    this.state = FoldState.flat,
    this.orientation = FoldOrientation.horizontal,
    this.boundsLeft = 0,
    this.boundsTop = 0,
    this.boundsRight = 0,
    this.boundsBottom = 0,
  });

  static const FoldFeature none = FoldFeature._(foldable: false);

  /// Synthetic half-opened, horizontal-hinge (tabletop) feature used by the
  /// "force flex layout" preview: zero hinge bounds make [flexLayoutSplit]
  /// (flex_layout.dart) fall back to the window's middle, so the split lands
  /// mid-screen on any device.
  static const FoldFeature previewTabletop = FoldFeature._(
    foldable: true,
    state: FoldState.half,
    orientation: FoldOrientation.horizontal,
  );

  factory FoldFeature.fromNative(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return FoldFeature.none;
    final bounds = raw['bounds'] as List<dynamic>? ?? const [];
    return FoldFeature._(
      foldable: true,
      state: raw['state'] == 'half' ? FoldState.half : FoldState.flat,
      orientation: raw['orientation'] == 'vertical' ? FoldOrientation.vertical : FoldOrientation.horizontal,
      boundsLeft: _boundInt(bounds, 0),
      boundsTop: _boundInt(bounds, 1),
      boundsRight: _boundInt(bounds, 2),
      boundsBottom: _boundInt(bounds, 3),
    );
  }

  static int _boundInt(List<dynamic> bounds, int index) {
    final value = index < bounds.length ? bounds[index] : null;
    return value is int ? value : 0;
  }

  final bool foldable;
  final FoldState state;
  final FoldOrientation orientation;

  /// Device-pixel bounds of the hinge rectangle on the display.
  final int boundsLeft;
  final int boundsTop;
  final int boundsRight;
  final int boundsBottom;

  /// Hinge center in device pixels, X (for vertical hinges).
  double get hingeCenterX => (boundsLeft + boundsRight) / 2;

  /// Hinge center in device pixels, Y (for horizontal hinges).
  double get hingeCenterY => (boundsTop + boundsBottom) / 2;

  /// Half-opened with a horizontal hinge: tabletop posture, the display
  /// splits top and bottom.
  bool get isTabletop => foldable && state == FoldState.half && orientation == FoldOrientation.horizontal;

  /// Half-opened with a vertical hinge: book posture, the display splits
  /// left and right.
  bool get isBook => foldable && state == FoldState.half && orientation == FoldOrientation.vertical;

  @override
  bool operator ==(Object other) =>
      other is FoldFeature &&
      other.foldable == foldable &&
      other.state == state &&
      other.orientation == orientation &&
      other.boundsLeft == boundsLeft &&
      other.boundsTop == boundsTop &&
      other.boundsRight == boundsRight &&
      other.boundsBottom == boundsBottom;

  @override
  int get hashCode => Object.hash(foldable, state, orientation, boundsLeft, boundsTop, boundsRight, boundsBottom);

  @override
  String toString() =>
      'FoldFeature(foldable: $foldable, state: $state, orientation: $orientation, '
      'bounds: [$boundsLeft, $boundsTop, $boundsRight, $boundsBottom])';
}

/// Watches the native fold-feature stream and exposes the current window fold
/// state to the rest of the app.
///
/// The native side ([FoldFeatureMonitor]) pushes only on change and replays
/// the last state to listeners that attach late, so the initial state is
/// available as soon as [init] has run. [init] is idempotent and a no-op on
/// every platform other than Android.
class FoldFeatureService extends ChangeNotifier {
  FoldFeatureService._();

  static final FoldFeatureService instance = FoldFeatureService._();

  static const EventChannel _channel = EventChannel('com.plezy/fold_feature');

  FoldFeature _current = FoldFeature.none;
  FoldFeature get current => _current;

  StreamSubscription<dynamic>? _subscription;

  /// Starts watching the native channel. Call once at startup.
  void init() {
    if (_subscription != null || !Platform.isAndroid) return;
    foldLog('service: listening');
    _subscription = _channel.receiveBroadcastStream().listen((raw) {
      final next = FoldFeature.fromNative(raw);
      final repeat = next == _current;
      foldLog('payload: raw=$raw -> $next${repeat ? ' (repeat)' : ''}');
      if (repeat) return;
      _current = next;
      notifyListeners();
    });
  }

  /// Test seam: sets the reported feature without the native channel.
  @visibleForTesting
  void setForTesting(FoldFeature next) {
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
