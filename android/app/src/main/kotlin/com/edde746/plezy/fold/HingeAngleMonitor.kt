package com.edde746.plezy.fold

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Publishes the device's physical hinge angle (fold posture) to Dart as it
 * changes.
 *
 * [FoldFeatureMonitor] reports the window's [androidx.window.layout.FoldingFeature],
 * but on a single full-screen window the platform keeps that feature's
 * [androidx.window.layout.FoldingFeature.State] FLAT at every physical angle —
 * the window is never "separated" into two logical displays. The hinge angle
 * sensor ([Sensor.TYPE_HINGE_ANGLE], API 30+) is the authoritative posture
 * source: it reports the physical fold angle continuously, so a mid-range
 * angle (half-opened / tent / book) is distinguishable from flat and closed,
 * which the window geometry alone cannot tell apart.
 *
 * Only posture *transitions* are forwarded (the [bent] classification flips),
 * plus one initial emission, so the stream is an event trace rather than a
 * per-sample feed. On every device without the sensor — and on API levels
 * below 30 — the stream emits a single `available=false` payload and stays
 * silent, which the Dart side treats as "fall back to window geometry".
 *
 * Every observable step is mirrored to [FoldLogSink] (`plezy-fold.log`).
 */
class HingeAngleMonitor(
  private val channel: EventChannel,
  private val context: Context,
  private val sink: FoldLogSink? = null,
) : SensorEventListener {

  private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)
  private val attached = AtomicBoolean(false)
  private var sensorManager: SensorManager? = null
  private var sensor: Sensor? = null
  private var lastBent: Boolean? = null
  private var lastPayload: Map<String, Any?>? = null

  /** Wires the channel so Dart listeners receive the current state immediately. */
  fun attach() {
    if (!attached.compareAndSet(false, true)) return
    channel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sinkRef.set(events)
        val replay = lastPayload
        sink?.append("hinge", "onListen replay=${if (replay == null) "none" else "last-payload"}")
        replay?.let { events?.success(it) }
      }

      override fun onCancel(arguments: Any?) {
        sink?.append("hinge", "onCancel")
        sinkRef.set(null)
      }
    })
  }

  /**
   * Starts observing the hinge angle. Must run on the main thread with a live
   * context. Registers the sensor listener when the device exposes
   * [Sensor.TYPE_HINGE_ANGLE] (API 30+); otherwise emits `available=false`
   * once so the Dart side can fall back to window geometry.
   */
  fun start() {
    val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    sensorManager = manager
    sensor = if (manager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      manager.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
    } else {
      null
    }
    if (sensor == null || manager == null) {
      sink?.append("hinge", "start: no hinge-angle sensor (sdk=${Build.VERSION.SDK_INT}) -> unavailable")
      emit(available = false, angle = null, bent = false, force = true)
      return
    }
    manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    sink?.append("hinge", "start: hinge-angle sensor active (${sensor?.getStringType()})")
  }

  /** Stops observing. Safe to call more than once. */
  fun stop() {
    sensorManager?.unregisterListener(this)
    sensorManager = null
    sensor = null
    sink?.append("hinge", "stop")
    sinkRef.set(null)
  }

  override fun onSensorChanged(event: SensorEvent) {
    if (event.sensor.type != Sensor.TYPE_HINGE_ANGLE) return
    val angle = event.values[0]
    val bent = classifyBent(angle)
    if (bent == lastBent) return
    lastBent = bent
    sink?.append("hinge", "angle=${String.format(java.util.Locale.US, "%.1f", angle)}deg bent=$bent")
    emit(available = true, angle = angle.toDouble(), bent = bent)
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
    // Deliberately unused: the angle's raw value is the posture signal.
  }

  private fun emit(available: Boolean, angle: Double?, bent: Boolean, force: Boolean = false) {
    val payload = payloadFor(available, angle, bent)
    if (!force && payload == lastPayload) return
    lastPayload = payload
    sinkRef.get()?.success(payload)
  }

  companion object {
    // Half-opened postures (tent, book, any partial fold) span the mid-range
    // of the hinge angle; flat and closed sit at the extremes. The range is
    // polarity-independent: it does not matter whether 0deg means closed or
    // open, because "bent" is the middle, not a specific end.
    private const val BENT_MIN_DEGREES = 30.0
    private const val BENT_MAX_DEGREES = 150.0

    /** True when [angleDegrees] is a half-opened (bent) posture. */
    internal fun classifyBent(angleDegrees: Float): Boolean =
      angleDegrees >= BENT_MIN_DEGREES && angleDegrees <= BENT_MAX_DEGREES

    /**
     * Encodes a hinge-posture reading for the Dart side. [angle] is null when
     * the device has no hinge-angle sensor; the Dart side keys the flex
     * decision off [bent] only when [available].
     */
    internal fun payloadFor(available: Boolean, angle: Double?, bent: Boolean): Map<String, Any?> = mapOf(
      "available" to available,
      "angle" to angle,
      "bent" to bent,
    )
  }
}