import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_source_info.dart';
import '../../../models/livetv_capture_buffer.dart';
import '../../../mpv/mpv.dart';
import '../../../widgets/video_controls/icons.dart';
import '../../../widgets/video_controls/widgets/circular_control_button.dart';
import '../../../widgets/video_controls/widgets/live_timeline_bar.dart';
import '../../../widgets/video_controls/widgets/play_pause_stream_builder.dart';
import '../../../widgets/video_controls/widgets/video_timeline_bar.dart';

/// Compact media-controls panel for the foldable flex layout.
///
/// Renders centered in the half of the bent display opposite the video
/// surface: under the video in tabletop posture, beside it in book posture.
/// It reuses the player's transport callbacks and the standard timeline bars
/// so behavior matches the full-screen chrome.
class FlexControlsPanel extends StatelessWidget {
  final Player player;
  final MediaItem metadata;
  final List<MediaChapter> chapters;
  final bool chaptersLoaded;
  final int seekTimeSmall;

  final bool isLive;
  final bool canControl;
  final String? liveChannelName;
  final CaptureBuffer? captureBuffer;
  final bool isAtLiveEdge;
  final int Function(Duration)? liveEpochForPosition;
  final ValueChanged<int>? onLiveSeek;
  final VoidCallback? onJumpToLive;

  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final Future<void> Function(Duration)? onSeekRequested;
  final VoidCallback onPlayPause;

  /// Whether the "force compact controls" setting is on (drives the toggle's
  /// amber state; on a foldable the split itself is keyed on the bent
  /// posture, on a non-foldable it previews in portrait).
  final bool forceFlex;

  /// Toggles the "force flex layout" setting in place; the owning screen
  /// rebuilds the split decision.
  final VoidCallback onToggleForceFlex;

  const FlexControlsPanel({
    super.key,
    required this.player,
    required this.metadata,
    required this.chapters,
    required this.chaptersLoaded,
    required this.seekTimeSmall,
    required this.isLive,
    required this.canControl,
    required this.onPlayPause,
    required this.forceFlex,
    required this.onToggleForceFlex,
    this.liveChannelName,
    this.captureBuffer,
    this.isAtLiveEdge = true,
    this.liveEpochForPosition,
    this.onLiveSeek,
    this.onJumpToLive,
    this.onNext,
    this.onPrevious,
    this.onSeekRequested,
  });

  void _seek(Duration position) {
    final seek = onSeekRequested;
    if (!canControl || seek == null) return;
    unawaited(seek(position));
  }

  void _skip({required bool forward}) {
    _seek(player.state.position + Duration(seconds: forward ? seekTimeSmall : -seekTimeSmall));
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTitleRow(),
        const SizedBox(height: 8),
        _buildTimeline(),
        const SizedBox(height: 12),
        _buildTransportRow(),
      ],
    );

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      // Centered in whichever half the split assigns the panel, in both
      // tabletop (bottom half) and book (right half) postures.
      child: Align(alignment: Alignment.center, child: content),
    );
  }

  Widget _buildTitleRow() {
    final liveName = liveChannelName;
    final title = isLive && liveName != null ? liveName : metadata.displayTitle;
    final subtitle = isLive ? null : metadata.displaySubtitle;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        // Preview/force toggle: flips the "force flex layout" setting in
        // place (the split stays active with or without fold detection).
        const SizedBox(width: 8),
        IconButton(
          tooltip: t.settings.forceFlexLayout,
          icon: Icon(
            Symbols.unfold_more_rounded,
            size: 20,
            color: forceFlex ? Colors.amber : Colors.white54,
          ),
          onPressed: onToggleForceFlex,
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    if (isLive) {
      final buffer = captureBuffer;
      if (buffer == null || liveEpochForPosition == null) return const SizedBox.shrink();
      return Row(
        children: [
          Expanded(
            child: LiveTimelineBar(
              player: player,
              captureBuffer: buffer,
              epochForPosition: liveEpochForPosition!,
              isAtLiveEdge: isAtLiveEdge,
              onSeekEnd: onLiveSeek,
              horizontalLayout: false,
              enabled: canControl,
            ),
          ),
          if (!isAtLiveEdge && onJumpToLive != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CircularControlButton(
                semanticLabel: t.liveTv.goToLive,
                icon: Symbols.stream_rounded,
                iconSize: 40,
                onPressed: canControl ? onJumpToLive : null,
              ),
            ),
        ],
      );
    }

    return VideoTimelineBar(
      player: player,
      chapters: chapters,
      chaptersLoaded: chaptersLoaded,
      // The compact panel has no scrub preview; the seek lands on release.
      onSeek: (position) {},
      onSeekEnd: _seek,
      horizontalLayout: false,
      showFinishTime: true,
      enabled: canControl,
    );
  }

  Widget _buildTransportRow() {
    return PlayPauseStreamBuilder(
      player: player,
      builder: (context, isPlaying) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onPrevious != null)
              CircularControlButton(
                semanticLabel: t.videoControls.previousButton,
                icon: Symbols.skip_previous_rounded,
                iconSize: 40,
                onPressed: canControl ? onPrevious : null,
              ),
            if (!isLive) ...[
              if (onPrevious != null) const SizedBox(width: 16),
              CircularControlButton(
                semanticLabel: t.videoControls.seekBackwardButton(seconds: seekTimeSmall),
                icon: getReplayIcon(seekTimeSmall),
                iconSize: 40,
                onPressed: canControl ? () => _skip(forward: false) : null,
              ),
            ],
            const SizedBox(width: 16),
            CircularControlButton(
              semanticLabel: isPlaying ? t.videoControls.pauseButton : t.videoControls.playButton,
              icon: isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
              iconSize: 56,
              onPressed: canControl ? onPlayPause : null,
            ),
            if (!isLive) ...[
              const SizedBox(width: 16),
              CircularControlButton(
                semanticLabel: t.videoControls.seekForwardButton(seconds: seekTimeSmall),
                icon: getForwardIcon(seekTimeSmall),
                iconSize: 40,
                onPressed: canControl ? () => _skip(forward: true) : null,
              ),
            ],
            if (onNext != null)
              CircularControlButton(
                semanticLabel: t.videoControls.nextButton,
                icon: Symbols.skip_next_rounded,
                iconSize: 40,
                onPressed: canControl ? onNext : null,
              ),
          ],
        );
      },
    );
  }
}
