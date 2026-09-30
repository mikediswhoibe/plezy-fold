part of '../../video_player_screen.dart';

extension _VideoPlayerBuildMethods on VideoPlayerScreenState {
  static const double _videoLayoutSizeTolerance = 0.1;
  static const double _pinchZoomActivationThreshold = 0.06;
  static const int _pinchZoomActivationUpdateThreshold = 3;

  bool _isSameVideoLayoutSize(Size a, Size b) {
    return (a.width - b.width).abs() <= _videoLayoutSizeTolerance &&
        (a.height - b.height).abs() <= _videoLayoutSizeTolerance;
  }

  void _scheduleVideoLayoutUpdate(Size newSize) {
    final currentPlayer = player;
    if (currentPlayer == null) return;

    final lastSize = _lastVideoLayoutSize;
    if (_lastVideoLayoutPlayer == currentPlayer && lastSize != null && _isSameVideoLayoutSize(lastSize, newSize)) {
      return;
    }

    _pendingVideoLayoutSize = newSize;
    if (_videoLayoutUpdateScheduled) return;
    _videoLayoutUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _videoLayoutUpdateScheduled = false;
      if (!mounted) return;

      final pendingSize = _pendingVideoLayoutSize;
      final currentPlayer = player;
      _pendingVideoLayoutSize = null;
      if (pendingSize == null || currentPlayer == null) return;

      // The video region is dispatched on every layout update, not just on a
      // size change: a dpr change (moving the window between displays) leaves
      // the logical size identical while the device-pixel region the native
      // surface needs changes. The dedup is keyed on the region itself, and
      // normal full-screen playback (region stays null) never pays a
      // channel round-trip.
      final region = flexVideoRegion(
        _currentFlexSplit,
        MediaQuery.sizeOf(context),
        MediaQuery.devicePixelRatioOf(context),
      );
      if (region != _lastSentVideoRegion) {
        _lastSentVideoRegion = region;
        unawaited(
          region == null
              ? currentPlayer.setVideoRegion()
              : currentPlayer.setVideoRegion(
                  left: region.left,
                  top: region.top,
                  right: region.right,
                  bottom: region.bottom,
                ),
        );
      }

      final lastSize = _lastVideoLayoutSize;
      if (_lastVideoLayoutPlayer == currentPlayer &&
          lastSize != null &&
          _isSameVideoLayoutSize(lastSize, pendingSize)) {
        return;
      }

      _lastVideoLayoutSize = pendingSize;
      _lastVideoLayoutPlayer = currentPlayer;
      _videoFilterManager?.updatePlayerSize(pendingSize);
      unawaited(currentPlayer.updateFrame());
    });
  }

  PlaybackSourceSubtitleChoice? _selectedSourceSubtitleChoiceForControls(List<MediaSubtitleTrack> tracks) {
    if (tracks.isEmpty) return null;
    if (widget.isLive) {
      // Live selection is owned by the session state, not a PlaybackSession.
      final selected = _live.selectedSubtitle;
      return selected == null
          ? const PlaybackSourceSubtitleChoice.off()
          : PlaybackSourceSubtitleChoice.source(selected.id);
    }
    final selection = _playbackSession?.subtitleSelection;
    if (selection != null) {
      if (selection.isOff) return const PlaybackSourceSubtitleChoice.off();
      final sourceId = selection.primarySourceStreamId;
      if (sourceId != null && tracks.any((track) => track.id == sourceId)) {
        return PlaybackSourceSubtitleChoice.source(sourceId);
      }
    }
    // No fallback to `MediaSubtitleTrack.selected`. That flag is the server's
    // *request* (Plex `Stream.selected`, Jellyfin `DefaultSubtitleStreamIndex`)
    // and feeds `TrackSelectionService.selectSubtitleTrack` Priority 2 as an
    // input; it is never a report of what the resolver settled on, and live
    // tune metadata can carry it stale. Reading it back here ticked rows that
    // were never selected.
    return const PlaybackSourceSubtitleChoice.off();
  }

  List<PlaybackSubtitleSidecar> _sourceSubtitleSidecarsForControls() =>
      _playbackSession?.context.result.subtitleSidecars ?? const <PlaybackSubtitleSidecar>[];

  List<MediaSubtitleTrack> _sourceSubtitleTracksForControls() {
    if (widget.isLive) {
      // The live session lists only server-deliverable (burnable) streams;
      // in-band captions stay in the native player track list.
      return _live.session?.subtitleTracks ?? const <MediaSubtitleTrack>[];
    }
    final sidecarSourceIds = {for (final sidecar in _sourceSubtitleSidecarsForControls()) ?sidecar.sourceStreamId};
    return selectableSourceSubtitleTracks(
      _currentMediaInfo?.subtitleTracks ?? const <MediaSubtitleTrack>[],
      isTranscoding: _isTranscoding,
      sidecarSourceIds: sidecarSourceIds,
    );
  }

  Widget _buildLoadingSpinner() {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: PlayerLoadingIndicator()),
    );
  }

  /// The screen's failure surface, shared by a core that failed to start and
  /// a media open that failed after it did. Retry is the primary action and
  /// takes focus explicitly: a child `autofocus` never fires here, because
  /// the screen-level [Focus] claims the scope while the loading spinner is
  /// up and Flutter drops a later autofocus request once the scope already
  /// has a focused child. See [VideoPlayerScreenState._initializationErrorFocusNode].
  Widget _buildPlaybackFailure(String message, {required VoidCallback onRetry}) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: .min,
              children: [
                const AppIcon(Symbols.error_rounded, color: Colors.white70, size: 44, fill: 1),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: .center,
                  children: [
                    FocusableButton(
                      focusNode: _initializationErrorFocusNode,
                      onPressed: onRetry,
                      child: FilledButton(onPressed: onRetry, child: Text(t.common.retry)),
                    ),
                    const SizedBox(width: 12),
                    FocusableButton(
                      onPressed: () => unawaited(_handleBackButton()),
                      child: OutlinedButton(
                        onPressed: () => unawaited(_handleBackButton()),
                        child: Text(t.common.back),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startMobileZoomGesture() {
    // Pinch-to-zoom is one of the optional touch gestures (#1810).
    if (!SettingsService.instance.read(SettingsService.gesturePinchToZoom)) return;
    final filterManager = _videoFilterManager;
    if (filterManager == null || _isPinchZooming) return;

    _isPinchZooming = true;
    _pinchZoomActivationUpdateCount = 0;
    _pinchZoomChanged = false;
    _pinchStartZoomScale = filterManager.zoomScale;
  }

  void _clearMobileZoomGesture() {
    _isPinchZooming = false;
    _pinchZoomActivationUpdateCount = 0;
    _pinchZoomChanged = false;
    _pinchStartZoomScale = null;
  }

  Widget _buildVideoPlayer(BuildContext context) {
    // Cache platform detection to avoid multiple calls
    final isMobile = PlatformDetector.isMobile(context);
    final hideChromeOnMouseExit = !(isMobile && !PlatformDetector.isTV());

    // Foldable flex layout: a split of the player screen at the hinge —
    // video on the upright half, compact controls on the other half. The
    // decision is owned by flexDecisionFor: the hinge-angle sensor is the
    // authoritative posture signal (bent → split, flat/closed → standard
    // controls) with the window geometry only as a fallback where the sensor
    // is absent; force mode is orientation-keyed on a non-foldable.
    final fold = FoldFeatureService.instance.current;
    final posture = HingePostureService.instance.current;
    final flexEnabled = SettingsService.instance.read(SettingsService.flexLayout);
    final forceFlex = SettingsService.instance.read(SettingsService.forceFlexLayout);
    final windowSize = MediaQuery.sizeOf(context);
    final decision = flexDecisionFor(
      fold,
      window: windowSize,
      flexEnabled: flexEnabled,
      force: forceFlex,
      posture: posture,
    );
    final flexMode = decision.mode;
    final effectiveFold = decision.feature;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final split = flexLayoutSplit(flexMode, effectiveFold, windowSize, devicePixelRatio: devicePixelRatio);

    // The native video surface (beneath the Flutter view) only follows the
    // split through an explicit setVideoRegion; remember this frame's split
    // for the post-frame dispatch in _scheduleVideoLayoutUpdate.
    _currentFlexSplit = split;

    // A tabletop split is only meaningful in portrait (video top, controls
    // bottom), so while one is active the orientation is pinned to portrait,
    // overriding the screen's base policy (the landscape lock); when the
    // split goes away (flat/closed posture) the base policy is restored. The
    // entry path already applied the base policy, so this only acts on
    // changes and never touches the immersive UI mode.
    final flexTabletop = split != null && split.mainAxis == Axis.vertical;
    final rotationLocked = SettingsService.instance.read(SettingsService.rotationLocked);
    final orientationKey = flexTabletop ? 1 : (rotationLocked ? 2 : 3);
    if (_lastFlexOrientationKey != orientationKey) {
      _lastFlexOrientationKey = orientationKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (orientationKey) {
          case 1:
            unawaited(OrientationHelper.lockPortraitOrientation());
          case 2:
            unawaited(OrientationHelper.lockLandscapeOrientation());
          default:
            unawaited(OrientationHelper.restoreDefaultOrientations());
        }
      });
    }

    // Diagnostics: log the decision only when its inputs change, so the file
    // log is an event trace rather than per-frame spam.
    final decisionKey = '$fold|posture=$posture|$flexEnabled|$forceFlex|$flexMode|$split|$windowSize';
    if (_lastFoldDecisionLog != decisionKey) {
      _lastFoldDecisionLog = decisionKey;
      foldLog(
        'decision: state=$fold hinge=$posture enabled=$flexEnabled forced=$forceFlex '
        'mode=$flexMode split=$split window=${windowSize.width}x${windowSize.height} dpr=$devicePixelRatio',
      );
    }

    // Back handling (sheet-close + player exit) is owned by the OverlaySheetHost
    // that wraps this widget — see video_player_screen.dart (canPop/onSystemBack).
    return Scaffold(
      // Use transparent background on macOS when native video layer is active
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent, // Allow taps to pass through to controls
        onScaleStart: (details) {
          if (!isMobile) return;
          if (details.pointerCount >= 2) _startMobileZoomGesture();
        },
        onScaleUpdate: (details) {
          if (!isMobile) return;
          if (details.pointerCount < 2) return;
          if (!_isPinchZooming) _startMobileZoomGesture();

          final startZoom = _pinchStartZoomScale;
          final filterManager = _videoFilterManager;
          if (!_isPinchZooming || startZoom == null || filterManager == null) return;
          // Snap through 100% so pinching back undoes a zoom exactly, which is
          // the touch path to an unzoomed picture (#1505).
          final nextZoomScale = VideoFilterManager.normalizeZoomScale(
            VideoFilterManager.snapPinchZoomScale(startZoom * details.scale),
          );

          if (!_pinchZoomChanged) {
            if ((details.scale - 1.0).abs() <= _pinchZoomActivationThreshold) {
              _pinchZoomActivationUpdateCount = 0;
              return;
            }

            _pinchZoomActivationUpdateCount++;
            if (_pinchZoomActivationUpdateCount < _pinchZoomActivationUpdateThreshold) return;
            if (nextZoomScale == filterManager.zoomScale) return;

            _pinchZoomChanged = true;
            _ambientLightingService?.disable();
          }

          filterManager.setZoomScale(nextZoomScale);
        },
        onScaleEnd: (details) {
          if (!isMobile) return;
          if (!_isPinchZooming) return;
          if (!_pinchZoomChanged) {
            _clearMobileZoomGesture();
            return;
          }

          final zoomScale = _videoFilterManager?.zoomScale ?? 1.0;
          _visualEffects.showZoomToast(zoomScale);
          _clearMobileZoomGesture();
          _setPlayerState(() {});
        },
        child: PlayerChromeInteractionRegion(
          controller: _chromeController,
          hideOnExit: hideChromeOnMouseExit,
          child: Stack(
            children: [
              // macOS PiP placeholder — video is in PiP window, show background with icon
              // Placed before Video so controls render on top
              if (Platform.isMacOS) const VideoPlayerMacPipPlaceholder(),
              _buildPlayerSurface(context, split: split),
              // Netflix-style auto-play overlay (hidden in PiP mode)
              VideoPlayerPlayNextOverlay(
                visible: _episode.showPlayNextDialog,
                nextEpisode: _episode.next,
                autoPlayCountdown: _episode.autoPlayCountdown,
                cancelFocusNode: _playNextCancelFocusNode,
                confirmFocusNode: _playNextConfirmFocusNode,
                chromeController: _chromeController,
                onCancel: _cancelAutoPlay,
                onPlayNext: _playNext,
              ),
              // "Still watching?" overlay (hidden in PiP mode)
              VideoPlayerStillWatchingOverlay(
                visible: _showStillWatchingPrompt,
                countdown: _stillWatchingCountdown,
                pauseFocusNode: _stillWatchingPauseFocusNode,
                continueFocusNode: _stillWatchingContinueFocusNode,
                chromeController: _chromeController,
                onPause: _onStillWatchingPause,
                onContinue: _onStillWatchingContinue,
              ),
              // Buffering indicator (also shows during initial load, but not when exiting)
              // Hidden in PiP mode
              VideoPlayerBufferingOverlay(
                isBuffering: _isBuffering,
                hasFirstFrame: _firstFrame.uiReady,
                isExiting: _isExiting,
              ),
              // Watch Together overlays (isolated from video surface repaints)
              const VideoPlayerWatchTogetherOverlays(),
              // Black overlay during exit (no spinner - just covers transparency)
              VideoPlayerExitOverlay(isExiting: _isExiting),
            ],
          ),
        ),
      ),
    );
  }

  /// The player surface: the video area (with the full controls chrome
  /// overlaid) and, when a flex split is active, the compact controls panel
  /// on the half of the bent display opposite the video.
  ///
  /// In flex mode the video is constrained to the region before the hinge
  /// (top in tabletop, left in book): the native surface beneath the Flutter
  /// view is confined to that region by the explicit `setVideoRegion`
  /// dispatch in `_scheduleVideoLayoutUpdate` (its letterboxing inside the
  /// region is the core's normal job), and the full controls chrome is
  /// suppressed in favor of the compact panel.
  Widget _buildPlayerSurface(BuildContext context, {required FlexLayoutSplit? split}) {
    // Authority and navigation callbacks are shared by the video chrome and
    // the flex panel, so they are computed once here instead of inside the
    // layout closure.
    var authority = (canControlPlayback: true, canNavigateMediaItems: true);
    try {
      authority = context.select<WatchTogetherProvider, ({bool canControlPlayback, bool canNavigateMediaItems})>(
        (wt) => (
          canControlPlayback: !wt.isInSession || wt.canControl(),
          canNavigateMediaItems: !wt.isInSession || wt.isHost,
        ),
      );
    } catch (_) {
      // Watch Together is optional outside the main app shell.
    }
    if (_lastMediaControlAuthority != authority) {
      _lastMediaControlAuthority = authority;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_mediaControls.syncAvailability());
      });
    }

    // The screen answers next/previous once for every entry point; the
    // buttons add only the in-flight and room authority gates so a control
    // cannot look live while it does nothing. Live TV is never room-bound,
    // and its zap debounces itself through the transition gate.
    final canNavigateItems = widget.isLive || authority.canNavigateMediaItems;
    final onNext = _hasNextItem && !_episode.isLoadingNext && canNavigateItems ? _navigateToNextItem : null;
    final onPrevious = _hasPreviousItem && canNavigateItems ? _navigateToPreviousItem : null;
    // The force flag drives the panel's in-place toggle; the split itself was
    // already decided in _buildVideoPlayer from the same preference.
    final forceFlex = SettingsService.instance.read(SettingsService.forceFlexLayout);

    final videoArea = LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleVideoLayoutUpdate(newSize);

        final sourceAudioTracks = _currentMediaInfo?.audioTracks ?? const <MediaAudioTrack>[];
        final sourceSubtitleSidecars = _sourceSubtitleSidecarsForControls();
        final sourceSubtitleTracks = _sourceSubtitleTracksForControls();

        return Video(
          player: player!,
          hasFirstFrame: _firstFrame.uiReady,
          // The full controls chrome is replaced by the split panel in flex
          // mode; the video region carries the surface only.
          controls: split == null
              ? (context) => PlexVideoControls(
                  player: player!,
                  volumeController: _volumeController!,
                  metadata: _currentMetadata,
                  onNext: onNext,
                  onPrevious: onPrevious,
                  availableVersions: _availableVersions,
                  selectedMediaIndex: _effectiveSelectedMediaIndex,
                  selectedQualityPreset: _selectedQualityPreset,
                  serverSupportsTranscoding: _serverSupportsTranscoding,
                  isTranscoding: _isTranscoding,
                  isOfflinePlayback: _isOfflinePlayback,
                  sourceAudioTracks: sourceAudioTracks,
                  selectedAudioStreamId: _selectedAudioStreamId,
                  sourceSubtitleTracks: sourceSubtitleTracks,
                  selectedSubtitleChoice: _selectedSourceSubtitleChoiceForControls(sourceSubtitleTracks),
                  selectedSecondarySubtitleStreamId: _playbackSession?.subtitleSelection.secondarySourceStreamId,
                  sourceSubtitleSidecars: sourceSubtitleSidecars,
                  sourcePartId: _currentMediaInfo?.partId,
                  onPlaybackSourceChanged: _switchPlaybackSource,
                  onTogglePIPMode: _togglePIPMode,
                  boxFitMode: _videoFilterManager?.boxFitMode ?? 0,
                  videoZoomScale: _videoFilterManager?.zoomScale ?? 1.0,
                  onCycleBoxFitMode: _visualEffects.cycleBoxFitMode,
                  onVideoZoomChanged: _visualEffects.setZoom,
                  onZoomIn: _visualEffects.zoomIn,
                  onZoomOut: _visualEffects.zoomOut,
                  onResetVideoZoom: _visualEffects.resetZoom,
                  onCycleAudioTrack: _cycleAudioTrack,
                  onCycleSubtitleTrack: _cycleSubtitleTrack,
                  onAudioTrackChanged: _onAudioTrackChanged,
                  onSubtitleTrackChanged: _onSubtitleTrackChanged,
                  onSecondarySubtitleTrackChanged: _onSecondarySubtitleTrackChanged,
                  onSeekRequested: _seekPlayback,
                  onRateRequested: _setPlaybackRate,
                  onPlayPauseRequested: _handleControlsTransport,
                  onBack: _handleBackButton,
                  onReachedEnd: ({skipAutoPlayCountdown = false}) =>
                      _onVideoCompleted(true, skipAutoPlayCountdown: skipAutoPlayCountdown),
                  canControl: authority.canControlPlayback,
                  canNavigateMediaItems: authority.canNavigateMediaItems,
                  hasFirstFrame: _firstFrame.uiReady,
                  playNextFocusNode: _episode.showPlayNextDialog ? _playNextConfirmFocusNode : null,
                  playbackPromptOpen: _showStillWatchingPrompt,
                  chromeController: _chromeController,
                  shaderService: _shaderService,
                  // ignore: no-empty-block - state update triggers rebuild to reflect shader change
                  onShaderChanged: () => _setPlayerState(() {}),
                  thumbnailDataBuilder: _scrubPreviewSource?.isAvailable == true ? _getThumbnailData : null,
                  isLive: widget.isLive,
                  liveChannelName: _live.channelName,
                  captureBuffer: _live.captureBuffer,
                  isAtLiveEdge: _live.atLiveEdge,
                  liveEpochForPosition: widget.isLive ? _liveEpochForPosition : null,
                  onLiveSeek: _live.captureBuffer != null ? _seekLiveToEpoch : null,
                  onLiveSeekBy: _live.captureBuffer != null ? _liveSeek.seekBy : null,
                  onJumpToLive: _live.captureBuffer != null && !_live.atLiveEdge ? _jumpToLiveEdge : null,
                  isAmbientLightingEnabled: _ambientLightingService?.isEnabled ?? false,
                  onToggleAmbientLighting: _ambientLightingService?.isSupported == true
                      ? _visualEffects.toggleAmbientLighting
                      : null,
                  toastController: _toastController,
                )
              : null,
        );
      },
    );

    if (split == null) return Center(child: videoArea);

    final panel = FlexControlsPanel(
      player: player!,
      metadata: _currentMetadata,
      chapters: _currentMediaInfo?.chapters ?? const <MediaChapter>[],
      chaptersLoaded: _currentMediaInfo != null,
      seekTimeSmall: SettingsService.instance.read(SettingsService.seekTimeSmall),
      isLive: widget.isLive,
      canControl: authority.canControlPlayback,
      liveChannelName: _live.channelName,
      captureBuffer: _live.captureBuffer,
      isAtLiveEdge: _live.atLiveEdge,
      liveEpochForPosition: widget.isLive ? _liveEpochForPosition : null,
      onLiveSeek: _live.captureBuffer != null ? _seekLiveToEpoch : null,
      onJumpToLive: _live.captureBuffer != null && !_live.atLiveEdge ? _jumpToLiveEdge : null,
      onNext: onNext,
      onPrevious: onPrevious,
      onSeekRequested: _seekPlayback,
      onPlayPause: () => unawaited(_handleControlsTransport(TransportCommand.toggle)),
      forceFlex: forceFlex,
      onToggleForceFlex: () {
        foldLog('forceFlexLayout toggled -> ${!forceFlex} (from flex panel)');
        SettingsService.instance.write(SettingsService.forceFlexLayout, !forceFlex);
        _setPlayerState(() {});
      },
    );

    if (split.mainAxis == Axis.vertical) {
      // Tabletop: video above the hinge, controls below it.
      return Column(
        children: [
          SizedBox(height: split.videoExtent, width: double.infinity, child: videoArea),
          Expanded(child: panel),
        ],
      );
    }
    // Book: video left of the hinge, controls to its right.
    return Row(
      children: [
        SizedBox(width: split.videoExtent, height: double.infinity, child: videoArea),
        Expanded(child: panel),
      ],
    );
  }
}
