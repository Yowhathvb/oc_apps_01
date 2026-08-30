import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/post_model.dart';
import 'create_post_screen.dart';
import 'media_profile_screen.dart';
import 'user_profile_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'notification_screen.dart';
import '../utils/mention_parser.dart';
import '../utils/mention_input.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  List<PostModel> _posts = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _offset = 0;
  final int _limit = 10;
  final ScrollController _scrollController = ScrollController();
  String? _myUserId;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    _fetchPosts();
    _fetchUnreadCount();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isFetchingMore) {
        _fetchMorePosts();
      }
    });
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
    setState(() {
      _myUserId = prefs.getString('user_id');
    });
  }

  Future<void> _fetchPosts() async {
    setState(() {
      _isLoading = true;
      _offset = 0;
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
          _posts = dataList.map((json) => PostModel.fromJson(json)).toList();
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
            _posts.addAll(dataList.map((json) => PostModel.fromJson(json)).toList());
          } else {
            // No more posts
            _offset -= _limit; // Revert offset
          }
        }
      });
    }
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
      // Update follow state for all posts by the same author
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

  void _goToUserProfile(String userId) {
    if (userId == _myUserId) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaProfileScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen()));
                  _fetchUnreadCount(); // Refresh count after returning
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
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaProfileScreen()));
            },
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _fetchPosts,
            child: _posts.isEmpty 
              ? const Center(child: Text("Belum ada postingan"))
              : ListView.separated(
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
                    return _buildPostCard(_posts[index]);
                  },
                ),
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit),
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostScreen()));
          if (result == true) {
            _fetchPosts();
          }
        },
      ),
    );
  }

  Widget _buildPostCard(PostModel post) {
    final isMe = post.authorId == _myUserId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Avatar and vertical line (Threads style)
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
                          post.authorName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                        )
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Right column: Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => _goToUserProfile(post.authorId),
                      child: Row(
                        children: [
                          Text(
                            post.authorName + (isMe ? " (Anda)" : ""), 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "• ${timeago.format(post.createdAt)}", 
                            style: const TextStyle(color: Colors.grey, fontSize: 13)
                          ),
                        ],
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
                        onTap: () {
                          _showPostOptions(post, isMe);
                        },
                        child: const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
                      ),
                  ],
                ),
                if (post.caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MentionParser.buildText(context, post.caption, style: const TextStyle(fontSize: 15), myUserId: _myUserId),
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
                      onTap: () {
                        _showComments(post);
                      },
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
                        if (res['success'] != true) {
                          if (mounted) {
                            setState(() { 
                              post.isShared = originalShared;
                              post.sharesCount = originalCount;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengubah status repost')));
                          }
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
                        if (res['success'] != true) {
                          if (mounted) {
                            setState(() { 
                              post.isSaved = originalSaved;
                              post.savesCount = originalCount;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengubah status simpan')));
                          }
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
      }
    ).then((_) {
      // Hanya perbarui UI untuk jumlah komentar, tidak perlu memuat ulang seluruh post (yang memicu loading screen)
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
                  onTap: () {
                    Navigator.pop(context);
                    // API Call for delete can be placed here
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Postingan dihapus (Simulasi)')));
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
      }
    );
  }

  Widget _buildActionButton({required IconData icon, required Color? color, required int count, required VoidCallback onTap}) {
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal')));
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
                            title: Text(c['authorName'].toString() + (isMe ? ' (Anda)' : ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: MentionParser.buildText(context, c['text'].toString(), myUserId: widget.myUserId),
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
