import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/media_view_settings.dart';
import '../models/post_model.dart';
import '../services/api_service.dart';
import '../utils/mention_input.dart';
import '../utils/mention_parser.dart';
import '../widgets/media_video_player.dart';
import '../widgets/post_audio_player.dart';
import '../widgets/post_poll_card.dart';
import '../widgets/reels_view.dart';
import '../widgets/video_view_settings_sheet.dart';
import 'create_post_screen.dart';
import 'media_profile_screen.dart';
import 'notification_screen.dart';
import 'user_profile_screen.dart';

class MediaScreen extends StatefulWidget {
  final ValueListenable<bool>? isPageVisibleListenable;
  final ValueChanged<bool>? onReelsFullscreenChanged;

  const MediaScreen({
    super.key,
    this.isPageVisibleListenable,
    this.onReelsFullscreenChanged,
  });

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<ReelsViewState> _reelsKey = GlobalKey<ReelsViewState>();
  final ScrollController _scrollController = ScrollController();

  List<PostModel> _posts = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _offset = 0;
  final int _limit = 10;
  String? _myUserId;
  int _unreadCount = 0;

  int _activeTabIndex = 0; // 0 = Feed (kiri), 1 = Reels (kanan)
  bool _isScreenVisible = true;
  bool _isParentPageVisible = true;

  bool get _effectiveVisible => _isScreenVisible && _isParentPageVisible;

  MediaViewSettings _viewConfig = MediaViewSettings.defaults;
  int _unlockedVideoCount = 1;
  final Set<int> _forcedRenderIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.isPageVisibleListenable != null) {
      _isParentPageVisible = widget.isPageVisibleListenable!.value;
      widget.isPageVisibleListenable!.addListener(_onParentVisibilityChanged);
    }
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _activeTabIndex) {
        setState(() {
          _activeTabIndex = _tabController.index;
        });
        widget.onReelsFullscreenChanged?.call(_activeTabIndex == 1);
      }
    });

    _loadMyUserId();
    _loadViewSettings();
    _fetchPosts();
    _fetchUnreadCount();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isFetchingMore) {
        _fetchMorePosts();
      }
    });
  }

  void _onParentVisibilityChanged() {
    if (!mounted || widget.isPageVisibleListenable == null) return;
    setState(() {
      _isParentPageVisible = widget.isPageVisibleListenable!.value;
    });
  }

  @override
  void dispose() {
    widget.isPageVisibleListenable?.removeListener(_onParentVisibilityChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadViewSettings() async {
    final local = await MediaViewSettings.loadLocal();
    if (mounted) {
      setState(() => _viewConfig = local);
    }

    final res = await ApiService.getVideoViewSettings();
    if (res['success'] == true && res['viewConfig'] is Map && mounted) {
      final serverCfg = MediaViewSettings.fromJson(
        Map<String, dynamic>.from(res['viewConfig'] as Map),
      );
      await serverCfg.saveLocal();
      if (mounted) {
        setState(() => _viewConfig = serverCfg);
      }
    }
  }

  Future<void> _fetchUnreadCount() async {
    final count = await ApiService.getUnreadNotificationCount();
    if (mounted) {
      setState(() {
        _unreadCount = count;
      });
    }
  }

  Future<void> _loadMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _myUserId = prefs.getString('user_id');
      });
    }
  }

  Future<void> _fetchPosts() async {
    setState(() {
      _isLoading = true;
      _offset = 0;
      _unlockedVideoCount = 1;
      _forcedRenderIds.clear();
    });

    final res = await ApiService.getPosts(limit: _limit, offset: _offset);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          final responseData = res['data'];
          List dataList = [];
          if (responseData is List) {
            dataList = responseData;
          } else if (responseData != null && responseData is Map) {
            if (responseData.containsKey('posts')) {
              dataList = responseData['posts'];
            } else if (responseData.containsKey('data')) {
              dataList = responseData['data'];
            }
          }
          _posts = dataList.map((json) => PostModel.fromJson(Map<String, dynamic>.from(json))).toList();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal mengambil postingan')),
          );
        }
      });
    }
  }

  Future<void> _fetchMorePosts() async {
    if (_isFetchingMore) return;

    setState(() {
      _isFetchingMore = true;
      _offset += _limit;
    });

    final res = await ApiService.getPosts(limit: _limit, offset: _offset);

    if (mounted) {
      setState(() {
        _isFetchingMore = false;
        if (res['success'] == true) {
          final responseData = res['data'];
          List dataList = [];
          if (responseData is List) {
            dataList = responseData;
          } else if (responseData != null && responseData is Map) {
            if (responseData.containsKey('posts')) {
              dataList = responseData['posts'];
            } else if (responseData.containsKey('data')) {
              dataList = responseData['data'];
            }
          }

          if (dataList.isNotEmpty) {
            _posts.addAll(
              dataList.map((json) => PostModel.fromJson(Map<String, dynamic>.from(json))).toList(),
            );
          } else {
            _offset -= _limit;
          }
        }
      });
    }
  }

  void _onFeedVideoRendered(int queuePos) {
    if (!mounted) return;
    if (queuePos >= _unlockedVideoCount) {
      setState(() {
        _unlockedVideoCount = queuePos + 1;
      });
    }
  }

  Map<int, int> _buildVideoQueueIndexMap() {
    final map = <int, int>{};
    int idx = 0;
    for (final p in _posts) {
      if (p.mediaType == 'video' && p.mediaUrl != null) {
        idx++;
        map[p.id] = idx;
      }
    }
    return map;
  }

  Future<void> _openCreatePost({bool initialVideoMode = false}) async {
    setState(() => _isScreenVisible = false);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreatePostScreen(initialVideoMode: initialVideoMode)),
    );
    if (!mounted) return;
    setState(() => _isScreenVisible = true);
    if (result == 'video') {
      await Future.wait([
        _fetchPosts(),
        _reelsKey.currentState?.refreshReels() ?? Future.value(),
      ]);
    } else if (result == true) {
      await _fetchPosts();
    }
  }

  void _openViewSettings() {
    showModalBottomSheet<MediaViewSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoViewSettingsSheet(
        initialSettings: _viewConfig,
        onChanged: (next) {
          if (mounted) {
            setState(() => _viewConfig = next);
          }
        },
      ),
    );
  }

  Future<void> _toggleLike(PostModel post) async {
    final originalState = post.isLiked;
    setState(() {
      post.isLiked = !post.isLiked;
      if (post.isLiked) {
        post.likesCount++;
      } else {
        post.likesCount--;
      }
    });

    final res = await ApiService.likePost(post.id);
    if (res['success'] != true) {
      if (mounted) {
        setState(() {
          post.isLiked = originalState;
          if (post.isLiked) {
            post.likesCount++;
          } else {
            post.likesCount--;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengubah like')),
        );
      }
    }
  }

  Future<void> _toggleFollow(PostModel post) async {
    final originalState = post.isFollowing;
    setState(() {
      post.isFollowing = !post.isFollowing;
      for (var p in _posts) {
        if (p.authorId == post.authorId) {
          p.isFollowing = post.isFollowing;
        }
      }
    });

    final res = await ApiService.toggleFollow(post.authorId);
    if (res['success'] != true) {
      if (mounted) {
        setState(() {
          post.isFollowing = originalState;
          for (var p in _posts) {
            if (p.authorId == post.authorId) {
              p.isFollowing = post.isFollowing;
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengikuti/batal mengikuti')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(post.isFollowing ? 'Berhasil mengikuti' : 'Berhasil berhenti mengikuti')),
        );
      }
    }
  }

  Future<void> _goToUserProfile(String userId) async {
    setState(() => _isScreenVisible = false);
    if (userId == _myUserId) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaProfileScreen()));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
    }
    if (mounted) {
      setState(() => _isScreenVisible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    final isReelsTab = _activeTabIndex == 1;

    return PopScope(
      canPop: !isReelsTab,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isReelsTab) {
          _tabController.animateTo(0);
        }
      },
      child: Scaffold(
        backgroundColor: isReelsTab ? Colors.black : null,
        appBar: isReelsTab
            ? null
            : AppBar(
                title: const Text('Our Media'),
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.lightBlueAccent,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dynamic_feed, size: 18),
                          SizedBox(width: 6),
                          Text('Feed'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_collection_outlined, size: 18),
                          SizedBox(width: 6),
                          Text('Reels'),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Atur View Video',
                    onPressed: _openViewSettings,
                    icon: const Icon(Icons.tune),
                  ),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        onPressed: () async {
                          setState(() => _isScreenVisible = false);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationScreen(),
                            ),
                          );
                          if (mounted) {
                            setState(() => _isScreenVisible = true);
                            _fetchUnreadCount();
                          }
                        },
                        icon: const Icon(Icons.notifications_none),
                      ),
                      if (_unreadCount > 0)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              _unreadCount > 99 ? '99+' : '$_unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    onPressed: () async {
                      setState(() => _isScreenVisible = false);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MediaProfileScreen(),
                        ),
                      );
                      if (mounted) setState(() => _isScreenVisible = true);
                    },
                    icon: const Icon(Icons.person_outline),
                  ),
                ],
              ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // KIRI: Feed Postingan (Teks, Foto, Video dengan render 1-per-1)
            _buildFeedTab(),
            // KANAN: Our Reels (Video vertikal swipe, full layar)
            ReelsView(
              key: _reelsKey,
              viewConfig: _viewConfig,
              isTabActive: _effectiveVisible && _activeTabIndex == 1,
              myUserId: _myUserId,
              onBackToFeed: () => _tabController.animateTo(0),
              onOpenProfile: _goToUserProfile,
              onShowComments: _showComments,
              onOpenUploadVideo: () => _openCreatePost(initialVideoMode: true),
              onOpenViewSettings: _openViewSettings,
              onServerViewConfigLoaded: (cfg) {
                setState(() => _viewConfig = cfg);
                cfg.saveLocal();
              },
            ),
          ],
        ),
        floatingActionButton: isReelsTab
            ? null
            : FloatingActionButton(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                child: const Icon(Icons.edit),
                onPressed: () => _openCreatePost(initialVideoMode: false),
              ),
      ),
    );
  }

  Widget _buildFeedTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchPosts,
        child: ListView(
          children: const [
            SizedBox(height: 200),
            Center(child: Text('Belum ada postingan')),
          ],
        ),
      );
    }

    final videoQueueMap = _buildVideoQueueIndexMap();

    if (_viewConfig.layout == 'grid') {
      return RefreshIndicator(
        onRefresh: _fetchPosts,
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.72,
          ),
          itemCount: _posts.length,
          itemBuilder: (context, index) {
            return _buildGridPostCard(_posts[index], videoQueueMap);
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPosts,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _posts.length + (_isFetchingMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildPostCard(_posts[index], videoQueueMap);
        },
      ),
    );
  }

  Widget _buildGridPostCard(PostModel post, Map<int, int> videoQueueMap) {
    final queuePos = videoQueueMap[post.id];
    final shouldRenderVideo = queuePos == null
        ? false
        : (!_viewConfig.sequentialRender ||
            queuePos <= _unlockedVideoCount ||
            _forcedRenderIds.contains(post.id));

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: post.mediaType == 'video' && post.mediaUrl != null
                ? MediaVideoPlayer(
                    key: ValueKey('grid_video_${post.id}'),
                    post: post,
                    viewConfig: _viewConfig,
                    shouldRender: shouldRenderVideo,
                    queuePosition: queuePos,
                    isActive: _effectiveVisible && _activeTabIndex == 0,
                    onRendered: () {
                      if (queuePos != null) _onFeedVideoRendered(queuePos);
                    },
                    onForceRender: () {
                      setState(() => _forcedRenderIds.add(post.id));
                    },
                  )
                : (post.mediaUrl != null && post.mediaType == 'audio')
                    ? Container(
                        color: const Color(0xFF1E293B),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.music_note_rounded, size: 36, color: Color(0xFF38BDF8)),
                            const SizedBox(height: 6),
                            Text(
                              post.caption.isNotEmpty ? post.caption : 'Audio / Musik',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                : (post.mediaUrl != null && post.mediaType == 'image')
                    ? Image.network(
                        ApiService.getServerUrl(post.mediaUrl!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, _, _) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF0F3460).withValues(alpha: 0.08),
                        padding: const EdgeInsets.all(10),
                        child: Center(
                          child: Text(
                            post.caption,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    post.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                GestureDetector(
                  onTap: () => _toggleLike(post),
                  child: Row(
                    children: [
                      Icon(
                        post.isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: post.isLiked ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 3),
                      Text('${post.likesCount}', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(PostModel post, Map<int, int> videoQueueMap) {
    final isMe = post.authorId == _myUserId;
    final queuePos = videoQueueMap[post.id];
    final shouldRenderVideo = queuePos == null
        ? false
        : (!_viewConfig.sequentialRender ||
            queuePos <= _unlockedVideoCount ||
            _forcedRenderIds.contains(post.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              GestureDetector(
                onTap: () => _goToUserProfile(post.authorId),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: post.authorAvatar != null
                      ? NetworkImage(ApiService.getServerUrl(post.authorAvatar!))
                      : null,
                  child: post.authorAvatar == null
                      ? Text(
                          post.authorName.isNotEmpty
                              ? post.authorName.substring(0, 1).toUpperCase()
                              : 'U',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                        )
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _goToUserProfile(post.authorId),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.authorName + (isMe ? ' (Anda)' : ''),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '• ${timeago.format(post.createdAt)}',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isMe)
                      GestureDetector(
                        onTap: () => _toggleFollow(post),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: post.isFollowing ? Colors.transparent : const Color(0xFF0F3460),
                            border: Border.all(color: const Color(0xFF0F3460)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            post.isFollowing ? 'Mengikuti' : 'Ikuti',
                            style: TextStyle(
                              color: post.isFollowing ? const Color(0xFF0F3460) : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => _showPostOptions(post, isMe),
                        child: const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
                      ),
                  ],
                ),
                if (post.caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MentionParser.buildText(
                    context,
                    post.caption,
                    style: const TextStyle(fontSize: 15),
                    myUserId: _myUserId,
                  ),
                ],
                if (post.poll != null) ...[
                  PostPollCard(
                    postId: post.id,
                    initialPoll: post.poll!,
                  ),
                ],
                if (post.mediaUrl != null && post.mediaType == 'audio') ...[
                  const SizedBox(height: 10),
                  PostAudioPlayer(
                    audioUrl: ApiService.getServerUrl(post.mediaUrl!),
                    title: post.caption.isNotEmpty ? post.caption : 'Musik / Audio',
                  ),
                ],
                if (post.mediaUrl != null && post.mediaType == 'image') ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      ApiService.getServerUrl(post.mediaUrl!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 250,
                      errorBuilder: (_, _, _) => Container(
                        height: 200,
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                      ),
                    ),
                  ),
                ],
                if (post.mediaUrl != null && post.mediaType == 'video') ...[
                  const SizedBox(height: 10),
                  MediaVideoPlayer(
                    key: ValueKey('feed_video_${post.id}'),
                    post: post,
                    viewConfig: _viewConfig,
                    shouldRender: shouldRenderVideo,
                    queuePosition: queuePos,
                    isActive: _effectiveVisible && _activeTabIndex == 0,
                    onRendered: () {
                      if (queuePos != null) _onFeedVideoRendered(queuePos);
                    },
                    onForceRender: () {
                      setState(() => _forcedRenderIds.add(post.id));
                    },
                    onViewRecorded: (_) {
                      if (mounted) setState(() {});
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildActionButton(
                      icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: post.isLiked ? Colors.red : Colors.grey[800],
                      count: post.likesCount,
                      onTap: () => _toggleLike(post),
                    ),
                    const SizedBox(width: 24),
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline,
                      color: Colors.grey[800],
                      count: post.commentsCount,
                      onTap: () => _showComments(post),
                    ),
                    const SizedBox(width: 24),
                    _buildActionButton(
                      icon: post.isShared ? Icons.close : Icons.repeat,
                      color: post.isShared ? Colors.red : Colors.grey[800],
                      count: post.sharesCount,
                      onTap: () async {
                        final originalShared = post.isShared;
                        final originalCount = post.sharesCount;
                        setState(() {
                          post.isShared = !post.isShared;
                          if (post.isShared) {
                            post.sharesCount++;
                          } else {
                            post.sharesCount--;
                          }
                        });
                        final res = await ApiService.repostPost(post.id);
                        if (res['success'] != true && mounted) {
                          setState(() {
                            post.isShared = originalShared;
                            post.sharesCount = originalCount;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gagal mengubah status repost')),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 24),
                    _buildActionButton(
                      icon: post.isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: post.isSaved ? Colors.amber : Colors.grey[800],
                      count: post.savesCount,
                      onTap: () async {
                        final originalSaved = post.isSaved;
                        final originalCount = post.savesCount;
                        setState(() {
                          post.isSaved = !post.isSaved;
                          if (post.isSaved) {
                            post.savesCount++;
                          } else {
                            post.savesCount--;
                          }
                        });
                        final res = await ApiService.savePost(post.id);
                        if (res['success'] != true && mounted) {
                          setState(() {
                            post.isSaved = originalSaved;
                            post.savesCount = originalCount;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gagal mengubah status simpan')),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 24),
                    _buildActionButton(
                      icon: Icons.send_outlined,
                      color: Colors.grey[800],
                      count: 0,
                      onTap: () {
                        final String shareText = "${post.authorName} membagikan postingan:\n\n${post.caption}";
                        Share.share(shareText);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showComments(PostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return CommentSheet(post: post, myUserId: _myUserId);
      },
    ).then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _showPostOptions(PostModel post, bool isMe) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Hapus Postingan', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    final res = await ApiService.deleteMediaPost(post.id.toString());
                    if (!mounted) return;
                    if (res['success'] == true) {
                      setState(() {
                        _posts.removeWhere((p) => p.id == post.id);
                      });
                      if (post.mediaType == 'video') {
                        _reelsKey.currentState?.refreshReels();
                      }
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Postingan berhasil dihapus')),
                      );
                    } else {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text(res['message'] ?? 'Gagal menghapus postingan')),
                      );
                    }
                  },
                ),
              if (!isMe)
                ListTile(
                  leading: const Icon(Icons.report_outlined, color: Colors.red),
                  title: const Text('Laporkan', style: TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(context),
                ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Salin Tautan'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color? color,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text(count.toString(), style: TextStyle(color: color)),
          ],
        ],
      ),
    );
  }
}

class CommentSheet extends StatefulWidget {
  final PostModel post;
  final String? myUserId;
  const CommentSheet({super.key, required this.post, this.myUserId});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    final res = await ApiService.getComments(widget.post.id);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _comments = res['data'];
        }
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    final res = await ApiService.addComment(widget.post.id, text);
    if (mounted) {
      setState(() {
        _isSending = false;
        if (res['success'] == true) {
          _commentController.clear();
          _comments.add(res['data']);
          widget.post.commentsCount++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal')),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('Komentar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(child: Text('Belum ada komentar untuk postingan ini.'))
                    : ListView.builder(
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final c = _comments[index];
                          final isMe = c['authorId'].toString() == widget.myUserId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey[300],
                              child: Text(c['authorName'].toString().substring(0, 1).toUpperCase()),
                            ),
                            title: Text(
                              c['authorName'].toString() + (isMe ? ' (Anda)' : ''),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: MentionParser.buildText(
                              context,
                              c['text'].toString(),
                              myUserId: widget.myUserId,
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: MentionInput(
                controller: _commentController,
                hintText: 'Tambahkan komentar...',
                isSending: _isSending,
                onSend: _sendComment,
              ),
            ),
          )
        ],
      ),
    );
  }
}
