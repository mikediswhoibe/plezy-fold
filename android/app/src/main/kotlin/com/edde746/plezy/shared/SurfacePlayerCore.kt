package com.edde746.plezy.shared

import android.graphics.Rect

/**
 * Surface and display concerns that the ExoPlayer and mpv cores implement
 * identically, so a plugin holding either one dispatches without branching
 * on which backend is active.
 *
 * Only backend-independent members belong here: playback control
 * (play/seek/track selection) stays off this interface because mpv drives it
 * through properties and commands where ExoPlayer uses direct method calls.
 */
interface SurfacePlayerCore {
  fun setVisible(visible: Boolean)
  fun updateFrame()
  fun onPipModeChanged(isInPipMode: Boolean)
  fun requestAudioFocus(): Boolean
  fun abandonAudioFocus()
  fun clearVideoFrameRate()
  fun setVideoFrameRate(
    fps: Float,
    videoDurationMs: Long,
    extraDelayMs: Long,
    videoWidth: Int,
    videoHeight: Int,
    matchResolution: Boolean,
    onComplete: (switched: Boolean) -> Unit
  )

  /**
   * Confine the video surface to [region] (device pixels, content-view
   * coordinates) or restore full window coverage when null. Foldable flex
   * layout calls this to letterbox the video into its half of a bent display.
   */
  fun setVideoRegion(region: Rect?)
}
