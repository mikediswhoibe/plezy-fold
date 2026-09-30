package com.edde746.plezy.fold

import android.graphics.Rect
import androidx.window.layout.FoldingFeature
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Payload encoding for the Dart side: [FoldFeatureMonitor.payloadFor] is the
 * contract between the native window-info observation and the flex-layout
 * decision on the Dart side, so it is pinned here.
 */
@RunWith(RobolectricTestRunner::class)
class FoldFeatureMonitorTest {

  @Test
  fun noFeatureIsEmptyMap() {
    assertTrue(FoldFeatureMonitor.payloadFor(null).isEmpty())
  }

  @Test
  fun halfOpenedHorizontalHingeIsTabletopPayload() {
    val payload = FoldFeatureMonitor.payloadFor(
      FakeFoldingFeature(Rect(0, 1400, 1440, 1480), FoldingFeature.Orientation.HORIZONTAL, FoldingFeature.State.HALF_OPENED),
    )

    assertEquals("half", payload["state"])
    assertEquals("horizontal", payload["orientation"])
    assertArrayEquals(intArrayOf(0, 1400, 1440, 1480), payload["bounds"] as IntArray)
  }

  @Test
  fun halfOpenedVerticalHingeIsBookPayload() {
    val payload = FoldFeatureMonitor.payloadFor(
      FakeFoldingFeature(Rect(696, 0, 744, 2220), FoldingFeature.Orientation.VERTICAL, FoldingFeature.State.HALF_OPENED),
    )

    assertEquals("half", payload["state"])
    assertEquals("vertical", payload["orientation"])
    assertArrayEquals(intArrayOf(696, 0, 744, 2220), payload["bounds"] as IntArray)
  }

  @Test
  fun flatFeatureReportsFlatState() {
    val payload = FoldFeatureMonitor.payloadFor(
      FakeFoldingFeature(Rect(0, 1100, 2220, 1120), FoldingFeature.Orientation.HORIZONTAL, FoldingFeature.State.FLAT),
    )

    assertEquals("flat", payload["state"])
    assertEquals("horizontal", payload["orientation"])
  }

  /**
   * The concrete feature implementations in androidx.window are Kotlin
   * internal, so the public interface is implemented directly.
   */
  private class FakeFoldingFeature(
    override val bounds: Rect,
    override val orientation: FoldingFeature.Orientation,
    override val state: FoldingFeature.State,
  ) : FoldingFeature {
    override val occlusionType: FoldingFeature.OcclusionType
      get() = FoldingFeature.OcclusionType.NONE

    override val isSeparating: Boolean = true
  }
}