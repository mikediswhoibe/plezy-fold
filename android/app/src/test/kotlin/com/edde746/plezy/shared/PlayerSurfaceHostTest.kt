package com.edde746.plezy.shared

import android.app.Activity
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.ColorDrawable
import android.view.SurfaceHolder
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodCall
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PlayerSurfaceHostTest {

  @Test
  fun scaffoldCreatesFullScreenBlackVideoLayerBehindFlutterContent() {
    val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    activity.setContentView(FrameLayout(activity))
    val callback = object : SurfaceHolder.Callback {
      override fun surfaceCreated(holder: SurfaceHolder) = Unit
      override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit
      override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
    }

    val container = PlayerSurfaceHost.createContainer(activity, clipChildren = true)
    val surface = PlayerSurfaceHost.createVideoSurface(activity, callback)
    container.addView(surface)
    val content = PlayerSurfaceHost.attachToContent(activity, container)

    assertSame(content, container.parent)
    assertEquals(0, content.indexOfChild(container))
    assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, container.layoutParams.width)
    assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, container.layoutParams.height)
    assertEquals(Color.BLACK, (container.background as ColorDrawable).color)
    assertTrue(container.clipChildren)
    assertEquals(FrameLayout.LayoutParams.MATCH_PARENT, surface.layoutParams.width)
    assertEquals(FrameLayout.LayoutParams.MATCH_PARENT, surface.layoutParams.height)
  }

  @Test
  fun applyVideoRegionConfinesTheContainerAndNullRestoresFullWindow() {
    val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    activity.setContentView(FrameLayout(activity))
    val container = PlayerSurfaceHost.createContainer(activity)
    PlayerSurfaceHost.attachToContent(activity, container)

    val region = Rect(0, 0, 1848, 1224)
    PlayerSurfaceHost.applyVideoRegion(container, region)
    val lp = container.layoutParams
    assertEquals(1848, lp.width)
    assertEquals(1224, lp.height)
    assertEquals(0, (lp as ViewGroup.MarginLayoutParams).leftMargin)
    assertEquals(0, lp.topMargin)

    // Re-applying the same region must not retrigger layout.
    PlayerSurfaceHost.applyVideoRegion(container, region)
    assertSame(lp, container.layoutParams)

    // A non-origin region rides on the margins, not the parent's gravity.
    PlayerSurfaceHost.applyVideoRegion(container, Rect(10, 20, 210, 120))
    assertEquals(200, container.layoutParams.width)
    assertEquals(100, container.layoutParams.height)
    assertEquals(10, (container.layoutParams as ViewGroup.MarginLayoutParams).leftMargin)
    assertEquals(20, (container.layoutParams as ViewGroup.MarginLayoutParams).topMargin)

    PlayerSurfaceHost.applyVideoRegion(container, null)
    assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, container.layoutParams.width)
    assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, container.layoutParams.height)
  }

  @Test
  fun videoRegionFromCallParsesValidRectsAndRejectsDegenerateOnes() {
    val valid = MethodCall(
      "setVideoRegion",
      mapOf("left" to 0, "top" to 0, "right" to 1848, "bottom" to 1224),
    )
    assertEquals(Rect(0, 0, 1848, 1224), PlayerSurfaceHost.videoRegionFromCall(valid))

    // Reset and malformed calls all mean "full window", never a broken layout.
    assertNull(PlayerSurfaceHost.videoRegionFromCall(MethodCall("setVideoRegion", null)))
    assertNull(
      PlayerSurfaceHost.videoRegionFromCall(
        MethodCall("setVideoRegion", mapOf("left" to 0, "top" to 0, "right" to 1848)),
      ),
    )
    assertNull(
      PlayerSurfaceHost.videoRegionFromCall(
        MethodCall("setVideoRegion", mapOf("left" to 0, "top" to 0, "right" to 0, "bottom" to 1224)),
      ),
    )
  }
}
