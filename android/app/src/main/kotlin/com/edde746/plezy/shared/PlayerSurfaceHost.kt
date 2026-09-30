package com.edde746.plezy.shared

import android.app.Activity
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import com.edde746.plezy.mpv.OsdPlanePolicy
import io.flutter.plugin.common.MethodCall

/** Shared Android view scaffold beneath the ExoPlayer and mpv cores. */
internal object PlayerSurfaceHost {
  /**
   * The black background is only ever visible where no below-window
   * SurfaceView punches the window: the GL-vo mpv paths, which hide the OSD
   * plane. With a full-size OSD/ASS plane in the container the whole player
   * is punched out of the window and the letterbox is that plane's pixels
   * instead; see [createOsdSurface].
   */
  fun createContainer(activity: Activity, clipChildren: Boolean = false): FrameLayout = FrameLayout(activity).apply {
    // FrameLayout.LayoutParams (a MarginLayoutParams) so [applyVideoRegion]
    // can reposition the container by margin without reparenting.
    layoutParams = FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT,
      FrameLayout.LayoutParams.MATCH_PARENT
    )
    setBackgroundColor(Color.BLACK)
    this.clipChildren = clipChildren
  }

  /**
   * Confines the surface container — and with it the video and OSD planes it
   * hosts — to [region] in device pixels relative to the container's parent
   * (the activity content view), or restores full window coverage when
   * [region] is null.
   *
   * Both cores letterbox the video inside whatever the container measures
   * (mpv through VideoRectPolicy, Exo through its AspectRatioFrameLayout),
   * so resizing the container is the whole video-side change; the Flutter
   * overlay owns the rest of the screen. No-op when the layout already
   * matches, so layout passes do not retrigger themselves.
   */
  fun applyVideoRegion(container: FrameLayout, region: Rect?) {
    val lp = container.layoutParams as? ViewGroup.MarginLayoutParams ?: return
    if (region == null) {
      if (lp.width == ViewGroup.LayoutParams.MATCH_PARENT &&
        lp.height == ViewGroup.LayoutParams.MATCH_PARENT &&
        lp.leftMargin == 0 &&
        lp.topMargin == 0
      ) {
        return
      }
      lp.width = ViewGroup.LayoutParams.MATCH_PARENT
      lp.height = ViewGroup.LayoutParams.MATCH_PARENT
      lp.leftMargin = 0
      lp.topMargin = 0
    } else {
      val width = region.width()
      val height = region.height()
      if (width <= 0 || height <= 0) return
      if (lp.width == width && lp.height == height && lp.leftMargin == region.left && lp.topMargin == region.top) {
        return
      }
      lp.width = width
      lp.height = height
      lp.leftMargin = region.left
      lp.topMargin = region.top
    }
    container.layoutParams = lp
  }

  /**
   * The video region a `setVideoRegion` call carries: a device-pixel rect, or
   * null when the surface should fill the window. Absent or degenerate
   * arguments mean "reset" rather than a broken layout, so a malformed call
   * can at worst restore the full-window surface.
   */
  fun videoRegionFromCall(call: MethodCall): Rect? {
    val args = call.arguments ?: return null
    val map = args as? Map<*, *> ?: return null
    val left = (map["left"] as? Number)?.toInt() ?: return null
    val top = (map["top"] as? Number)?.toInt() ?: return null
    val right = (map["right"] as? Number)?.toInt() ?: return null
    val bottom = (map["bottom"] as? Number)?.toInt() ?: return null
    if (right <= left || bottom <= top) return null
    return Rect(left, top, right, bottom)
  }

  fun createVideoSurface(activity: Activity, callback: SurfaceHolder.Callback): SurfaceView = SurfaceView(activity).apply {
    layoutParams = FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT,
      FrameLayout.LayoutParams.MATCH_PARENT
    )
    holder.addCallback(callback)
    setZOrderOnTop(false)
    setZOrderMediaOverlay(false)
    FlutterOverlayHelper.applyCompositionOrder(this, -2)
  }

  /**
   * Transparent plane directly above the video surface for the mpv
   * `vo=mediacodec` subtitle/OSD output. Media-overlay z-order keeps it above
   * the video SurfaceView but still beneath the Flutter window content.
   *
   * Being a full-size below-window SurfaceView, it punches the whole
   * container out of the window canvas, so the letterbox around the picture
   * is whatever this plane shows there. The fork fills those margins opaque
   * black (mpv-build patch 0106): a transparent margin scans out as the
   * compositor's own background, which MediaTek TV pipelines render above
   * black in HDR/Dolby Vision output (gray bars, #2163), and any extra layer
   * to paint them instead demotes the video plane to GPU composition and
   * drops the HDR output (#2287). Subtitles placed in the margins draw over
   * the fill in the same buffer.
   *
   * [renderScale] < 1 gives the plane a fixed buffer size below its view size
   * (see [OsdPlanePolicy]); mpv then rasterizes at that size and the
   * compositor scales the plane to the view. Re-applied on every layout so a
   * container resize keeps the ratio.
   */
  fun createOsdSurface(activity: Activity, callback: SurfaceHolder.Callback, renderScale: Float = 1f): SurfaceView = SurfaceView(activity).apply {
    layoutParams = FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT,
      FrameLayout.LayoutParams.MATCH_PARENT
    )
    holder.addCallback(callback)
    holder.setFormat(PixelFormat.TRANSLUCENT)
    setZOrderOnTop(false)
    setZOrderMediaOverlay(true)
    FlutterOverlayHelper.applyCompositionOrder(this, -1)
    if (renderScale < 1f) {
      addOnLayoutChangeListener { view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
        if (right - left == oldRight - oldLeft && bottom - top == oldBottom - oldTop) return@addOnLayoutChangeListener
        val size = OsdPlanePolicy.fixedSizeFor(right - left, bottom - top, renderScale) ?: return@addOnLayoutChangeListener
        (view as SurfaceView).holder.setFixedSize(size.width, size.height)
      }
    }
  }

  fun attachToContent(activity: Activity, container: FrameLayout): ViewGroup {
    val contentView = activity.findViewById<ViewGroup>(android.R.id.content)
    contentView.addView(container, 0)
    ensureFlutterOverlayOnTop(contentView, container)
    return contentView
  }

  fun ensureFlutterOverlayOnTop(contentView: ViewGroup, surfaceContainer: ViewGroup?): Boolean {
    val flutterContainer = FlutterOverlayHelper.findFlutterContainer(contentView, surfaceContainer)
      ?: return false
    if (contentView.getChildAt(contentView.childCount - 1) !== flutterContainer) {
      FlutterOverlayHelper.configureFlutterZOrder(contentView, flutterContainer, compositionOrder = 1)
    }
    return true
  }
}
