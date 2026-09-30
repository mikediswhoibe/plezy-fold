package com.edde746.plezy.fold

import android.app.Activity
import android.os.Build
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Publishes the activity window's [FoldingFeature] to Dart as it changes.
 *
 * Folding is a configuration change the manifest absorbs (no activity
 * restart), and the engine only re-applies system-UI state on resume, so a
 * live fold-state source is what the app needs to react to tabletop/book
 * postures (half-opened with a horizontal/vertical hinge).
 *
 * [WindowInfoTracker] requires API 29+ (the first foldables shipped on
 * Android 10); on older devices [start] is a no-op and the channel stays
 * silent. The layout-info flow emits the current state on collection and on
 * every window-info change; only state *changes* are forwarded, and the last
 * state is replayed to listeners that attach after the tracker has seen the
 * feature.
 *
 * Every observable step is mirrored to [FoldLogSink] (`plezy-fold.log`) so
 * the detection pipeline can be diagnosed on-device without adb.
 */
class FoldFeatureMonitor(
  private val channel: EventChannel,
  private val sink: FoldLogSink? = null,
) {

  private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)
  private var scope: CoroutineScope? = null
  private var lastPayload: Map<String, Any?>? = null

  /** Wires the channel so Dart listeners receive the current state immediately. */
  fun attach() {
    channel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sinkRef.set(events)
        val replay = lastPayload
        sink?.append("native", "onListen replay=${if (replay == null) "none" else "last-payload"}")
        replay?.let { events?.success(it) }
      }

      override fun onCancel(arguments: Any?) {
        sink?.append("native", "onCancel")
        sinkRef.set(null)
      }
    })
  }

  /**
   * Starts observing [activity]'s window. Must run on the main thread with a
   * live activity. The activity-scoped flow uses the platform
   * window-layout-info listener on API 33+ and the activity's window
   * listener below that.
   */
  fun start(activity: Activity) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      sink?.append("native", "start skipped: sdk < 29")
      return
    }
    if (scope != null) return
    val tracker = WindowInfoTracker.getOrCreate(activity)
    sink?.append("native", "start sdk=${Build.VERSION.SDK_INT} supportedPostures=${tracker.supportedPostures}")
    // Synchronous read at startup: the flow's first emission can arrive
    // before the window's display features are settled, so this is the
    // reference value for any "state never arrives" diagnosis.
    sink?.append("native", "initial-sync-read: ${describe(tracker.getCurrentWindowLayoutInfo(activity))}")
    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also {
      it.launch {
        var first = true
        tracker.windowLayoutInfo(activity).collect { info ->
          sink?.append("native", (if (first) "emission initial" else "emission change") + ": ${describe(info)}")
          first = false
          onWindowLayoutInfoChanged(info)
        }
      }
    }
  }

  /** Releases the observation. Safe to call more than once. */
  fun stop() {
    sink?.append("native", "stop")
    scope?.cancel()
    scope = null
    sinkRef.set(null)
  }

  private fun onWindowLayoutInfoChanged(info: WindowLayoutInfo) {
    val feature = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
    val payload = payloadFor(feature)
    if (payload == lastPayload) return
    lastPayload = payload
    sinkRef.get()?.success(payload)
  }

  private fun describe(info: WindowLayoutInfo): String {
    val features = info.displayFeatures
    val feature = features.filterIsInstance<FoldingFeature>().firstOrNull()
      ?: return "features=${features.map { it::class.simpleName }} (no FoldingFeature)"
    return "features=${features.map { it::class.simpleName }} " +
      "state=${if (feature.state == FoldingFeature.State.HALF_OPENED) "HALF_OPENED" else "FLAT"} " +
      "orientation=${if (feature.orientation == FoldingFeature.Orientation.HORIZONTAL) "HORIZONTAL" else "VERTICAL"} " +
      "bounds=${feature.bounds} separating=${feature.isSeparating}"
  }

  companion object {
    /**
     * Encodes a [FoldingFeature] for the Dart side: an empty map is "no fold
     * feature on this device". Hinge bounds are device-pixel coordinates;
     * Dart converts them to logical pixels with the device pixel ratio.
     */
    internal fun payloadFor(feature: FoldingFeature?): Map<String, Any?> = when {
      feature == null -> emptyMap()
      else ->
        mapOf(
          "state" to if (feature.state == FoldingFeature.State.HALF_OPENED) "half" else "flat",
          "orientation" to if (feature.orientation == FoldingFeature.Orientation.HORIZONTAL) "horizontal" else "vertical",
          "bounds" to intArrayOf(feature.bounds.left, feature.bounds.top, feature.bounds.right, feature.bounds.bottom),
        )
    }
  }
}