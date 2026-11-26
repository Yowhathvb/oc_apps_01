import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/media_view_settings.dart';
import '../models/post_model.dart';
import '../services/api_service.dart';
import '../utils/mention_parser.dart';
import 'media_video_player.dart';

/// Responsive scroll physics so vertical swipes in Reels advance easily
/// without requiring a heavy 50%-screen drag.
class _ReelsPageScrollPhysics extends PageScrollPhysics {
  const _ReelsPageScrollPhysics({super.parent});

  @override
  _ReelsPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ReelsPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingVelocity => 25.0;

  @override
  SpringDescription get spring => const SpringDescription(
    mass: 0.5,
    stiffness: 240.0,
    damping: 22.0,
  );
}

class ReelsView extends StatefulWidget {
  final MediaViewSettings viewConfig;
  final bool isTabActive;
  final String? myUserId;
  final VoidCallback? onBackToFeed;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<PostModel> onShowComments;
  final VoidCallback onOpenUploadVideo;
  final VoidCallback onOpenViewSettings;
  final ValueChanged<MediaViewSettings>? onServerViewConfigLoaded;

  const ReelsView({
    super.key,
    required this.viewConfig,
    required this.isTabActive,
    required this.myUserId,
    this.onBackToFeed,
    required this.onOpenProfile,
    required this.onShowComments,
    required this.onOpenUploadVideo,
    required this.onOpenViewSettings,
    this.onServerViewConfigLoaded,
  });

  @override
  State<ReelsView> createState() => ReelsViewState();
}

class ReelsViewState extends State<ReelsView>
    with AutomaticKeepAliveClientMixin {
  final PageController _verticalPageController = PageController();

  List<PostModel> _videos = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 10;
  String _sort = 'random';
  int _randomSeed = Random().nextInt(1000000);

  int _currentIndex = 0;
  int _unlockedReelCount = 1;
  final Set<int> _forcedRenderIds = {};
  final Map<int, bool> _playingMap = {};

  bool get _isCurrentReelPaused {
    if (_videos.isEmpty || _currentIndex >= _videos.length) return true;
    return !(_playingMap[_videos[_currentIndex].id] ?? false);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    refreshReels();
  }

  @override
  void dispose() {
    _verticalPageController.dispose();
    super.dispose();
  }

  Future<void> refreshReels() async {
    _randomSeed = Random().nextInt(1000000);
    final fetchLimit = _sort == 'random' ? 30 : _limit;
    setState(() {
      _isLoading = true;
      _offset = 0;
      _hasMore = true;
      _currentIndex = 0;
      _unlockedReelCount = 1;
      _forcedRenderIds.clear();
    });

    final res = await ApiService.getMediaVideos(
      limit: fetchLimit,
      offset: 0,
      sort: _sort,
      seed: _sort == 'random' ? _randomSeed : null,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (res['success'] == true) {
        final rawList = res['videos'] is List ? res['videos'] as List : [];
        final loaded = rawList
            .whereType<Map>()
            .map((e) => PostModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (_sort == 'random' && res['randomized'] != true) {
          loaded.shuffle(Random(_randomSeed));
        }
        _videos = loaded;
        _offset = loaded.length;
        final pagination = res['pagination'] is Map
            ? res['pagination'] as Map
            : {};
        _hasMore = pagination['hasMore'] == true;
        if (res['viewConfig'] is Map &&
            widget.onServerViewConfigLoaded != null) {
          widget.onServerViewConfigLoaded!(
            MediaViewSettings.fromJson(
              Map<String, dynamic>.from(res['viewConfig'] as Map),
            ),
          );
        }
      }
    });
    if (_verticalPageController.hasClients) {
      _verticalPageController.jumpToPage(0);
    }
  }

  Future<void> _fetchMoreReels() async {
    if (_isFetchingMore || !_hasMore) return;
    final requestOffset = _offset;
    setState(() {
      _isFetchingMore = true;
    });

    final res = await ApiService.getMediaVideos(
      limit: _limit,
      offset: requestOffset,
      sort: _sort,
      seed: _sort == 'random' ? _randomSeed : null,
    );

    if (!mounted) return;
    setState(() {
      _isFetchingMore = false;
      if (res['success'] == true) {
        final rawList = res['videos'] is List ? res['videos'] as List : [];
        final existingIds = _videos.map((v) => v.id).toSet();
        final more = rawList
            .whereType<Map>()
            .map((e) => PostModel.fromJson(Map<String, dynamic>.from(e)))
            .where((v) => !existingIds.contains(v.id))
            .toList();
        if (_sort == 'random' && res['randomized'] != true) {
          more.shuffle(Random(_randomSeed + requestOffset));
        }
        if (rawList.isNotEmpty) {
          _videos.addAll(more);
          _offset = requestOffset + rawList.length;
          final pagination = res['pagination'] is Map
              ? res['pagination'] as Map
              : {};
          _hasMore = pagination['hasMore'] == true;
        } else {
          _hasMore = false;
        }
      }
    });
  }

  void _onReelRendered(int oneBasedPos) {
    if (!mounted) return;
    if (oneBasedPos >= _unlockedReelCount) {
      setState(() {
        _unlockedReelCount = oneBasedPos + 1;
      });
    }
  }

  Future<void> _toggleLike(PostModel video) async {
    final original = video.isLiked;
    setState(() {
      video.isLiked = !video.isLiked;
      video.likesCount += video.isLiked ? 1 : -1;
    });
    final res = await ApiService.likePost(video.id);
    if (res['success'] != true && mounted) {
      setState(() {
        video.isLiked = original;
        video.likesCount += original ? 1 : -1;
      });
    }
  }

  Future<void> _toggleFollow(PostModel video) async {
    final original = video.isFollowing;
    setState(() {
      for (final v in _videos) {
        if (v.authorId == video.authorId) {
          v.isFollowing = !original;
        }
      }
    });
    final res = await ApiService.toggleFollow(video.authorId);
    if (res['success'] != true && mounted) {
      setState(() {
        for (final v in _videos) {
          if (v.authorId == video.authorId) {
            v.isFollowing = original;
          }
        }
      });
    }
  }

  Future<void> _toggleRepost(PostModel video) async {
    final original = video.isShared;
    setState(() {
      video.isShared = !video.isShared;
      video.sharesCount += video.isShared ? 1 : -1;
    });
    final res = await ApiService.repostPost(video.id);
    if (res['success'] != true && mounted) {
      setState(() {
        video.isShared = original;
        video.sharesCount += original ? 1 : -1;
      });
    }
  }

  Future<void> _toggleSave(PostModel video) async {
    final original = video.isSaved;
    setState(() {
      video.isSaved = !video.isSaved;
      video.savesCount += video.isSaved ? 1 : -1;
    });
    final res = await ApiService.savePost(video.id);
    if (res['success'] != true && mounted) {
      setState(() {
        video.isSaved = original;
        video.savesCount += original ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_videos.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.video_library_outlined,
                    color: Colors.white54,
                    size: 56,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada Reels video',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: widget.onOpenUploadVideo,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Upload Video Pertama'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F3460),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            PageView.builder(
              controller: _verticalPageController,
              scrollDirection: Axis.vertical,
              physics: const _ReelsPageScrollPhysics(),
              allowImplicitScrolling: true,
              dragStartBehavior: DragStartBehavior.down,
              itemCount: _videos.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _forcedRenderIds.add(_videos[index].id);
                });
                if (index >= _videos.length - 3) {
                  _fetchMoreReels();
                }
              },
              itemBuilder: (context, index) {
                final video = _videos[index];
                final queuePos = index + 1;
                final shouldRender =
                    !widget.viewConfig.sequentialRender ||
                    queuePos <= _unlockedReelCount ||
                    _forcedRenderIds.contains(video.id) ||
                    index == _currentIndex;

                return _buildReelPage(video, index, queuePos, shouldRender);
              },
            ),

          // Top-left Back Arrow (always visible, no background, +4px hit padding)
          if (widget.onBackToFeed != null)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, left: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onBackToFeed,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 26,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Top filter & action bar (only visible when paused or empty)
          if (_isCurrentReelPaused)
            Positioned(
              top: 0,
              left: widget.onBackToFeed != null ? 48 : 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _sortChip('random', 'Acak'),
                              const SizedBox(width: 6),
                              _sortChip('latest', 'Terbaru'),
                              const SizedBox(width: 6),
                              _sortChip('popular', 'Populer'),
                              const SizedBox(width: 6),
                              _sortChip('most_viewed', 'Terbanyak'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Muat Ulang Acak',
                        onPressed: refreshReels,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Atur View',
                        onPressed: widget.onOpenViewSettings,
                        icon: const Icon(Icons.tune, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Upload Video',
                        onPressed: widget.onOpenUploadVideo,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sortChip(String value, String label) {
    final active = _sort == value;
    return GestureDetector(
      onTap: () {
        if (_sort == value) return;
        setState(() => _sort = value);
        refreshReels();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.black45,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.white : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildReelPage(
    PostModel video,
    int index,
    int queuePos,
    bool shouldRender,
  ) {
    final isMe = video.authorId == widget.myUserId;
    final isActive = widget.isTabActive && index == _currentIndex;
    final isPaused = !(_playingMap[video.id] ?? false);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        MediaVideoPlayer(
          key: ValueKey('reel_${video.id}'),
          post: video,
          viewConfig: widget.viewConfig,
          shouldRender: shouldRender,
          queuePosition: queuePos,
          isActive: isActive,
          isReelsMode: true,
          onRendered: () => _onReelRendered(queuePos),
          onForceRender: () {
            setState(() => _forcedRenderIds.add(video.id));
          },
          onViewRecorded: (_) {
            if (mounted) setState(() {});
          },
          onPlayingChanged: (isPlaying) {
            if (mounted && _playingMap[video.id] != isPlaying) {
              setState(() {
                _playingMap[video.id] = isPlaying;
              });
            }
          },
        ),

        // Right-side Reels action buttons (Profile, Like, Komen, Share always visible; others only when paused)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          right: 12,
          bottom: bottomSafe + (isPaused ? 92 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Author Avatar + Follow (always visible)
              GestureDetector(
                onTap: () => widget.onOpenProfile(video.authorId),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.grey[700],
                      backgroundImage: video.authorAvatar != null
                          ? NetworkImage(
                              ApiService.getServerUrl(video.authorAvatar!),
                            )
                          : null,
                      child: video.authorAvatar == null
                          ? Text(
                              video.authorName.isNotEmpty
                                  ? video.authorName
                                        .substring(0, 1)
                                        .toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    if (!isMe && !video.isFollowing)
                      Positioned(
                        bottom: -7,
                        child: GestureDetector(
                          onTap: () => _toggleFollow(video),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Like (always visible)
              _reelActionIcon(
                icon: video.isLiked ? Icons.favorite : Icons.favorite_border,
                color: video.isLiked ? Colors.redAccent : Colors.white,
                label: '${video.likesCount}',
                onTap: () => _toggleLike(video),
              ),
              const SizedBox(height: 14),
              // Komen (always visible)
              _reelActionIcon(
                icon: Icons.chat_bubble_outline,
                color: Colors.white,
                label: '${video.commentsCount}',
                onTap: () => widget.onShowComments(video),
              ),
              if (isPaused) ...[
                const SizedBox(height: 14),
                _reelActionIcon(
                  icon: Icons.repeat,
                  color: video.isShared ? Colors.lightBlueAccent : Colors.white,
                  label: '${video.sharesCount}',
                  onTap: () => _toggleRepost(video),
                ),
                const SizedBox(height: 14),
                _reelActionIcon(
                  icon: video.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: video.isSaved ? Colors.amber : Colors.white,
                  label: '${video.savesCount}',
                  onTap: () => _toggleSave(video),
                ),
              ],
              const SizedBox(height: 14),
              // Share (always visible)
              _reelActionIcon(
                icon: Icons.send_outlined,
                color: Colors.white,
                label: 'Bagikan',
                onTap: () {
                  Share.share(
                    '${video.authorName} membagikan Reels:\n\n${video.caption}',
                  );
                },
              ),
            ],
          ),
        ),

        // Bottom-left profile & caption (always visible; stats only when paused)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          left: 14,
          right: 84,
          bottom: bottomSafe + (isPaused ? 92 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => widget.onOpenProfile(video.authorId),
                child: Row(
                  children: [
                    Text(
                      video.authorUsername.isNotEmpty
                          ? '@${video.authorUsername}'
                          : video.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${timeago.format(video.createdAt)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                    ),
                  ],
                ),
              ),
              if (video.caption.isNotEmpty) ...[
                const SizedBox(height: 6),
                MentionParser.buildText(
                  context,
                  video.caption,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                  ),
                  myUserId: widget.myUserId,
                ),
              ],
              if (isPaused && widget.viewConfig.controls.showStats) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _metaPill(Icons.visibility, '${video.viewsCount} tayangan'),
                    if (video.duration != null)
                      _metaPill(
                        Icons.timer_outlined,
                        '${video.duration!.round()}d',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _reelActionIcon({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 30,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 12),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
