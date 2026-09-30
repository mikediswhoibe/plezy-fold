import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Diagnostics sink for the fold-feature pipeline.
///
/// Every line is appended to `plezy-fold.log` in the app's external media
/// directory (`/sdcard/Android/media/com.edde746.plezy.fold/`, visible to
/// file managers), mirrored to the public Downloads folder
/// (`/sdcard/Download/plezy-fold-<package>.log`) and to the per-app files
/// directory, via the native [FoldLogSink]. The "sink init" line in the log
/// records which targets were live. No-op on non-Android platforms; channel
/// failures are swallowed because diagnostics must never affect playback.
const MethodChannel _channel = MethodChannel('com.plezy/fold_feature_log');

void foldLog(String message) {
  if (!Platform.isAndroid) return;
  unawaited(
    _channel.invokeMethod<void>('append', message).catchError((Object _) {}),
  );
}