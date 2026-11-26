import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../models/media_view_settings.dart';
import '../models/post_model.dart';
import '../services/api_service.dart';

class MediaVideoPlayer extends StatefulWidget {
  final PostModel post;
  final MediaViewSettings viewConfig;
  final bool shouldRender;
  final int? queuePosition;
  final bool isActive;
  final bool isReelsMode;
  final VoidCallback? onRendered;
  final VoidCallback? onForceRender;
  final ValueChanged<int>? onViewRecorded;
  final ValueChanged<bool>? onPlayingChanged;

  const MediaVideoPlayer({
    super.key,
    required this.post,
    required this.viewConfig,
    required this.shouldRender,
    this.queuePosition,
    this.isActive = true,
    this.isReelsMode = false,
    this.onRendered,
    this.onForceRender,
    this.onViewRecorded,
    this.onPlayingChanged,
  });

  @override
  State<MediaVideoPlayer> createState() => _MediaVideoPlayerState();
}

class _MediaVideoPlayerState extends State<MediaVideoPlayer> {
  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController? _controller;
  Timer? _safetyTimer;

  bool _isInitializing = false;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorDetail;
  bool _renderedNotified = false;
  bool _viewRecorded = false;
  bool _userPaused = false;
  bool _isDownloading = false;
  bool _isScrubbing = false;
  double _scrubValueMs = 0;
  bool? _lastReportedPlaying;

  bool? _mutedOverride;
  bool? _loopOverride;
  double? _speedOverride;
  String? _fitOverride;

  bool get _effectiveMuted =>
      _mutedOverride ?? (widget.isReelsMode ? false : widget.viewConfig.muted);
  bool get _effectiveLoop => _loopOverride ?? widget.viewConfig.loop;
  double get _effectiveSpeed =>
      _speedOverride ?? widget.viewConfig.defaultSpeed;
  String get _effectiveFit => _fitOverride ?? widget.viewConfig.objectFit;

  BoxFit get _boxFit {
    switch (_effectiveFit) {
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      default:
        return BoxFit.contain;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.shouldRender) {
      _initController();
    }
  }

  @override
  void didUpdateWidget(covariant MediaVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.shouldRender && widget.shouldRender) {
      _initController();
    }

    if (oldWidget.post.id != widget.post.id) {
      _disposeController();
      _renderedNotified = false;
      _viewRecorded = false;
      _userPaused = false;
      if (widget.shouldRender) {
        _initController();
      }
      return;
    }

    final controller = _controller;
    if (controller != null && _isInitialized) {
      if (oldWidget.viewConfig.muted != widget.viewConfig.muted ||
          oldWidget.viewConfig.loop != widget.viewConfig.loop ||
          oldWidget.viewConfig.defaultSpeed != widget.viewConfig.defaultSpeed) {
        controller.setVolume(_effectiveMuted ? 0.0 : 1.0);
        controller.setLooping(_effectiveLoop);
        controller.setPlaybackSpeed(_effectiveSpeed);
      }

      if (oldWidget.isActive != widget.isActive) {
        if (!widget.isActive) {
          if (controller.value.isPlaying) {
            controller.pause();
          }
          if (widget.isReelsMode) {
            _userPaused = false;
            controller.seekTo(Duration.zero);
          }
        } else if (widget.isReelsMode) {
          _userPaused = false;
          controller.seekTo(Duration.zero);
          controller.play();
        } else if (widget.viewConfig.autoplay && !_userPaused) {
          controller.play();
        }
      }
    }
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _safetyTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _isInitializing = false;
    _reportPlayingState(false);
  }

  void _reportPlayingState(bool isPlaying) {
    if (_lastReportedPlaying == isPlaying) return;
    _lastReportedPlaying = isPlaying;
    if (widget.onPlayingChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onPlayingChanged?.call(isPlaying);
      }
    });
  }

  void _notifyRenderedOnce() {
    if (_renderedNotified) return;
    _renderedNotified = true;
    _safetyTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onRendered?.call();
      }
    });
  }

  Future<void> _initController() async {
    if (_controller != null || _isInitializing) return;

    final candidates = <String>[];
    if (widget.post.streamUrl != null && widget.post.streamUrl!.isNotEmpty) {
      candidates.add(widget.post.streamUrl!);
    }
    if (widget.post.mediaUrl != null &&
        widget.post.mediaUrl!.isNotEmpty &&
        !candidates.contains(widget.post.mediaUrl)) {
      candidates.add(widget.post.mediaUrl!);
    }

    if (candidates.isEmpty) {
      _hasError = true;
      _errorDetail = 'URL video kosong';
      _notifyRenderedOnce();
      return;
    }

    setState(() {
      _isInitializing = true;
      _hasError = false;
      _errorDetail = null;
    });

    // Safety timeout: ensure queue never stalls if a video takes >12s to initialize
    _safetyTimer?.cancel();
    _safetyTimer = Timer(const Duration(seconds: 12), () {
      _notifyRenderedOnce();
    });

    final authHeaders = await ApiService.getAuthHeaders();
    authHeaders.remove('Content-Type');

    Object? lastError;

    for (final rawPath in candidates) {
      if (!mounted) return;
      final fullUrl = ApiService.getServerUrl(rawPath);
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(fullUrl),
        httpHeaders: authHeaders,
      );
      _controller = controller;
      controller.addListener(_onVideoTick);

      try {
        await controller.initialize();
        if (!mounted || _controller != controller) {
          controller.dispose();
          return;
        }
        await controller.setLooping(_effectiveLoop);
        await controller.setVolume(_effectiveMuted ? 0.0 : 1.0);
        await controller.setPlaybackSpeed(_effectiveSpeed);

        setState(() {
          _isInitializing = false;
          _isInitialized = true;
          _hasError = false;
          _errorDetail = null;
        });

        _notifyRenderedOnce();

        if (widget.isActive &&
            (widget.isReelsMode || widget.viewConfig.autoplay)) {
          await controller.play();
        }
        return;
      } catch (e) {
        lastError = e;
        controller.removeListener(_onVideoTick);
        await controller.dispose();
        if (_controller == controller) {
          _controller = null;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _hasError = true;
      _errorDetail = lastError?.toString();
    });
    _notifyRenderedOnce();
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final val = controller.value;

    _reportPlayingState(val.isPlaying);

    if (!_viewRecorded &&
        val.isPlaying &&
        val.position.inMilliseconds >= 1500) {
      _viewRecorded = true;
      _recordView();
    }

    if (!_isScrubbing) {
      setState(() {});
    }
  }

  Future<void> _recordView() async {
    final res = await ApiService.recordVideoView(widget.post.id);
    if (res['success'] == true && res['viewsCount'] != null && mounted) {
      final count = (res['viewsCount'] is num)
          ? (res['viewsCount'] as num).toInt()
          : int.tryParse(res['viewsCount'].toString()) ??
                widget.post.viewsCount + 1;
      setState(() {
        widget.post.viewsCount = count;
      });
      widget.onViewRecorded?.call(count);
    }
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        _userPaused = true;
        controller.pause();
      } else {
        _userPaused = false;
        controller.play();
      }
    });
  }

  void _toggleMute() {
    final next = !_effectiveMuted;
    setState(() {
      _mutedOverride = next;
    });
    _controller?.setVolume(next ? 0.0 : 1.0);
  }

  void _toggleLoop() {
    final next = !_effectiveLoop;
    setState(() {
      _loopOverride = next;
    });
    _controller?.setLooping(next);
  }

  void _cycleSpeed() {
    final currentIndex = _speedOptions.indexOf(_effectiveSpeed);
    final nextSpeed = _speedOptions[(currentIndex + 1) % _speedOptions.length];
    setState(() {
      _speedOverride = nextSpeed;
    });
    _controller?.setPlaybackSpeed(nextSpeed);
  }

  void _cycleFit() {
    const fits = ['contain', 'cover', 'fill'];
    final currentIdx = fits.indexOf(_effectiveFit);
    setState(() {
      _fitOverride = fits[(currentIdx + 1) % fits.length];
    });
  }

  Future<void> _downloadAndShareVideo() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final rawPath = widget.post.effectiveVideoPath;
      final dlUrl = ApiService.getServerUrl(
        rawPath.contains('?') ? '$rawPath&download=1' : '$rawPath?download=1',
      );
      final headers = await ApiService.getAuthHeaders();
      final response = await http.get(Uri.parse(dlUrl), headers: headers);
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}/ourchat_video_${widget.post.id}.mp4',
        );
        await file.writeAsBytes(response.bodyBytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: widget.post.caption.isNotEmpty
              ? widget.post.caption
              : 'Video dari OurChat',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal mengunduh video')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error unduh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _openFullscreen() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoDialog(
          controller: controller,
          post: widget.post,
          initialFit: _boxFit,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openMiniPip() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Mini Player',
      barrierColor: Colors.black26,
      pageBuilder: (ctx, _, _) {
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 90),
            child: Material(
              color: Colors.black,
              elevation: 12,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 220,
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.size.width > 0
                            ? controller.value.size.width
                            : 160,
                        height: controller.value.size.height > 0
                            ? controller.value.size.height
                            : 90,
                        child: VideoPlayer(controller),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: StatefulBuilder(
                        builder: (_, setMiniState) => GestureDetector(
                          onTap: () {
                            if (controller.value.isPlaying) {
                              controller.pause();
                            } else {
                              controller.play();
                            }
                            setMiniState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              controller.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  String _formatDuration(Duration d) {
    final totalSec = d.inSeconds;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String? _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildThumbnailBackground() {
    final thumbUrl = widget.post.thumbnailUrl;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      return Image.network(
        ApiService.getServerUrl(thumbUrl),
        fit: _boxFit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => Container(color: const Color(0xFF0D1B2A)),
      );
    }
    return Container(color: const Color(0xFF0D1B2A));
  }

  @override
  Widget build(BuildContext context) {
    final controls = widget.viewConfig.controls;
    final controller = _controller;

    if (widget.isReelsMode) {
      return _buildPlayerSurface(controls, controller);
    }

    final resolvedAspect = widget.viewConfig.resolveAspectRatio(
      _isInitialized && controller != null && controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : (widget.post.videoAspectRatio ?? (16 / 9)),
    );

    final maxHeight = widget.viewConfig.maxHeight.toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        color: Colors.black,
        constraints: BoxConstraints(maxHeight: maxHeight, minHeight: 190),
        child: Center(
          child: AspectRatio(
            aspectRatio: resolvedAspect ?? (9 / 16),
            child: _buildPlayerSurface(controls, controller),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSurface(
    MediaPlayerControlsConfig controls,
    VideoPlayerController? controller,
  ) {
    // Queued state (Sequential 1-per-1)
    if (!widget.shouldRender) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailBackground(),
          Container(color: Colors.black.withValues(alpha: 0.48)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.queuePosition != null
                            ? 'Antrian render #${widget.queuePosition}'
                            : 'Menunggu antrian render...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onForceRender != null) ...[
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: widget.onForceRender,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text(
                      'Muat Sekarang',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F3460),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (controls.showStats) _buildStatsOverlay(),
        ],
      );
    }

    // Error state
    if (_hasError) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailBackground(),
          Container(color: Colors.black.withValues(alpha: 0.65)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 36,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Gagal memuat video',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (_errorDetail != null && _errorDetail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _errorDetail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    _disposeController();
                    _initController();
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Coba lagi',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Loading state
    if (!_isInitialized || controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailBackground(),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'Memuat video...',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final val = controller.value;
    final durationMs = val.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final positionMs = _isScrubbing
        ? _scrubValueMs.clamp(0.0, durationMs)
        : val.position.inMilliseconds.toDouble().clamp(0.0, durationMs);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayPause,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video Surface: keeps original aspect ratio; non-portrait videos fill full width with black top/bottom
            FittedBox(
              fit: _boxFit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: val.size.width > 0 ? val.size.width : 1280,
                height: val.size.height > 0 ? val.size.height : 720,
                child: VideoPlayer(controller),
              ),
            ),

            // Buffering spinner
            if (val.isBuffering)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2.5,
                ),
              ),

            // Center Play Icon (only visible when paused)
            if (controls.showPlayPause && !val.isPlaying)
              Center(
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: widget.isReelsMode ? 44 : 34,
                    ),
                  ),
                ),
              ),

            // Top stats badge (only visible when paused in Feed mode)
            if (controls.showStats && !widget.isReelsMode && !val.isPlaying)
              _buildStatsOverlay(),

            // Bottom Control Bar (only visible when paused)
            if (!val.isPlaying)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    16,
                    10,
                    widget.isReelsMode
                        ? (MediaQuery.paddingOf(context).bottom + 6)
                        : 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.78),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controls.showSeekBar)
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: Colors.lightBlueAccent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: positionMs,
                            min: 0.0,
                            max: durationMs,
                            onChangeStart: (v) {
                              setState(() {
                                _isScrubbing = true;
                                _scrubValueMs = v;
                              });
                            },
                            onChanged: (v) {
                              setState(() => _scrubValueMs = v);
                            },
                            onChangeEnd: (v) async {
                              await controller.seekTo(
                                Duration(milliseconds: v.round()),
                              );
                              if (mounted) {
                                setState(() => _isScrubbing = false);
                              }
                            },
                          ),
                        ),
                      Row(
                        children: [
                          if (controls.showPlayPause)
                            _ctrlIcon(
                              icon: val.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              onTap: _togglePlayPause,
                            ),
                          if (controls.showTime)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(
                                '${_formatDuration(val.position)} / ${_formatDuration(val.duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (controls.showVolume)
                            _ctrlIcon(
                              icon: _effectiveMuted
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                              onTap: _toggleMute,
                            ),
                          if (controls.showSpeed)
                            GestureDetector(
                              onTap: _cycleSpeed,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_effectiveSpeed}x',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          if (controls.showLoop)
                            _ctrlIcon(
                              icon: Icons.repeat,
                              color: _effectiveLoop
                                  ? Colors.lightBlueAccent
                                  : Colors.white60,
                              onTap: _toggleLoop,
                            ),
                          if (controls.showFitToggle)
                            _ctrlIcon(
                              icon: _effectiveFit == 'cover'
                                  ? Icons.crop_free
                                  : (_effectiveFit == 'fill'
                                        ? Icons.aspect_ratio
                                        : Icons.fit_screen),
                              onTap: _cycleFit,
                            ),
                          if (controls.showPip && !widget.isReelsMode)
                            _ctrlIcon(
                              icon: Icons.picture_in_picture_alt,
                              onTap: _openMiniPip,
                            ),
                          if (controls.showDownload)
                            _isDownloading
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : _ctrlIcon(
                                    icon: Icons.download_rounded,
                                    onTap: _downloadAndShareVideo,
                                  ),
                          if (controls.showFullscreen)
                            _ctrlIcon(
                              icon: Icons.fullscreen,
                              onTap: _openFullscreen,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ctrlIcon({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildStatsOverlay() {
    final parts = <String>[];
    if (widget.post.width != null && widget.post.height != null) {
      parts.add('${widget.post.width}x${widget.post.height}');
    }
    final sizeText = _formatBytes(widget.post.compressedSize);
    if (sizeText != null) parts.add(sizeText);
    parts.add('${widget.post.viewsCount} views');

    if (parts.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          parts.join(' • '),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FullscreenVideoDialog extends StatefulWidget {
  final VideoPlayerController controller;
  final PostModel post;
  final BoxFit initialFit;

  const _FullscreenVideoDialog({
    required this.controller,
    required this.post,
    required this.initialFit,
  });

  @override
  State<_FullscreenVideoDialog> createState() => _FullscreenVideoDialogState();
}

class _FullscreenVideoDialogState extends State<_FullscreenVideoDialog> {
  late BoxFit _fit;

  @override
  void initState() {
    super.initState();
    _fit = widget.initialFit;
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final val = widget.controller.value;
    final maxMs = val.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final posMs = val.position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.post.authorName,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Switch Fit',
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              setState(() {
                _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (val.isPlaying) {
                  widget.controller.pause();
                } else {
                  widget.controller.play();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: _fit,
                    child: SizedBox(
                      width: val.size.width > 0 ? val.size.width : 1280,
                      height: val.size.height > 0 ? val.size.height : 720,
                      child: VideoPlayer(widget.controller),
                    ),
                  ),
                  if (!val.isPlaying)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white70,
                        size: 64,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      val.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (val.isPlaying) {
                        widget.controller.pause();
                      } else {
                        widget.controller.play();
                      }
                    },
                  ),
                  Expanded(
                    child: Slider(
                      value: posMs,
                      min: 0,
                      max: maxMs,
                      activeColor: Colors.lightBlueAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        widget.controller.seekTo(
                          Duration(milliseconds: v.round()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
