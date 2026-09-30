package com.edde746.plezy.fold

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Posture classification and payload encoding for the Dart side:
 * [HingeAngleMonitor.classifyBent] and [HingeAngleMonitor.payloadFor] are the
 * contract between the native hinge-angle observation and the flex-layout
 * decision on the Dart side, so they are pinned here.
 */
class HingeAngleMonitorTest {

  @Test
  fun midRangeAnglesAreBent() {
    assertTrue(HingeAngleMonitor.classifyBent(90f))
    assertTrue(HingeAngleMonitor.classifyBent(30f))
    assertTrue(HingeAngleMonitor.classifyBent(150f))
    assertTrue(HingeAngleMonitor.classifyBent(110f))
  }

  @Test
  fun extremeAnglesAreNotBent() {
    // Flat and closed sit at the extremes of the hinge angle; neither is a
    // half-opened (bent) posture. The range is polarity-independent, so both
    // ends classify as "not bent".
    assertFalse(HingeAngleMonitor.classifyBent(0f))
    assertFalse(HingeAngleMonitor.classifyBent(180f))
    assertFalse(HingeAngleMonitor.classifyBent(15f))
    assertFalse(HingeAngleMonitor.classifyBent(165f))
  }

  @Test
  fun availablePayloadCarriesAngleAndBent() {
    val payload = HingeAngleMonitor.payloadFor(available = true, angle = 90.0, bent = true)

    assertEquals(true, payload["available"])
    assertEquals(90.0, payload["angle"])
    assertEquals(true, payload["bent"])
  }

  @Test
  fun unavailablePayloadHasNullAngle() {
    val payload = HingeAngleMonitor.payloadFor(available = false, angle = null, bent = false)

    assertEquals(false, payload["available"])
    assertNull(payload["angle"])
    assertEquals(false, payload["bent"])
  }
}