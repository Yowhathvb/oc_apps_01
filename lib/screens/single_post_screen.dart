import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/post_model.dart';
import 'package:share_plus/share_plus.dart';
import 'user_profile_screen.dart';
import 'media_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/mention_parser.dart';
import '../utils/mention_input.dart';

class SinglePostScreen extends StatefulWidget {
  final int postId;
  const SinglePostScreen({super.key, required this.postId});

  @override
  State<SinglePostScreen> createState() => _SinglePostScreenState();
}

class _SinglePostScreenState extends State<SinglePostScreen> {
  PostModel? _post;
  bool _isLoading = true;
  String? _myUserId;
  
  final TextEditingController _commentController = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoadingComments = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    _fetchPost();
    _fetchComments();
  }

  Future<void> _loadMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUserId = prefs.getString('user_id');
    });
  }

  Future<void> _fetchPost() async {
    final res = await ApiService.getSinglePost(widget.postId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _post = PostModel.fromJson(res['data']);
        }
      });
    }
  }

  Future<void> _fetchComments() async {
    final res = await ApiService.getComments(widget.postId);
    if (mounted) {
      setState(() {
        _isLoadingComments = false;
        if (res['success'] == true) {
          _comments = res['data'];
        }
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _post == null) return;

    setState(() {
      _isSending = true;
    });

    final res = await ApiService.addComment(_post!.id, text);
    if (mounted) {
      setState(() {
        _isSending = false;
        if (res['success'] == true) {
          _commentController.clear();
          _comments.add(res['data']);
          _post!.commentsCount++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal')));
        }
      });
    }
  }

  void _goToUserProfile(String userId) {
    if (userId == _myUserId) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaProfileScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
    }
  }
  
  Future<void> _toggleLike() async {
    if (_post == null) return;
    final originalState = _post!.isLiked;
    setState(() {
      _post!.isLiked = !_post!.isLiked;
      if (_post!.isLiked) {
        _post!.likesCount++;
      } else {
        _post!.likesCount--;
      }
    });

    final res = await ApiService.likePost(_post!.id);
    if (res['success'] != true && mounted) {
      setState(() {
        _post!.isLiked = originalState;
        if (_post!.isLiked) {
          _post!.likesCount++;
        } else {
          _post!.likesCount--;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengubah like')));
    }
  }
  
  Future<void> _toggleFollow() async {
    if (_post == null) return;
    final originalState = _post!.isFollowing;
    setState(() {
      _post!.isFollowing = !_post!.isFollowing;
    });

    final res = await ApiService.toggleFollow(_post!.authorId);
    if (res['success'] != true && mounted) {
      setState(() {
        _post!.isFollowing = originalState;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengikuti/batal mengikuti')));
    }
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

  @override
  Widget build(BuildContext context) {
    final isMe = _post?.authorId == _myUserId;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Postingan'),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? const Center(child: Text('Postingan tidak ditemukan'))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // POST CONTENT
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => _goToUserProfile(_post!.authorId),
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.grey[300],
                                      backgroundImage: _post!.authorAvatar != null 
                                          ? NetworkImage(ApiService.getServerUrl(_post!.authorAvatar!))
                                          : null,
                                      child: _post!.authorAvatar == null
                                          ? Text(
                                              _post!.authorName.substring(0, 1).toUpperCase(),
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            GestureDetector(
                                              onTap: () => _goToUserProfile(_post!.authorId),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    _post!.authorName + (isMe ? " (Anda)" : ""),
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    "• ",
                                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (!isMe)
                                              GestureDetector(
                                                onTap: _toggleFollow,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: _post!.isFollowing ? Colors.transparent : const Color(0xFF0F3460),
                                                    border: Border.all(color: const Color(0xFF0F3460)),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    _post!.isFollowing ? 'Mengikuti' : 'Ikuti',
                                                    style: TextStyle(
                                                      color: _post!.isFollowing ? const Color(0xFF0F3460) : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (_post!.caption.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          MentionParser.buildText(context, _post!.caption, style: const TextStyle(fontSize: 15), myUserId: _myUserId),
                                        ],
                                        if (_post!.mediaUrl != null && _post!.mediaType == 'image') ...[
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(
                                              ApiService.getServerUrl(_post!.mediaUrl!),
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: 250,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            _buildActionButton(
                                              icon: _post!.isLiked ? Icons.favorite : Icons.favorite_border,
                                              color: _post!.isLiked ? Colors.red : Colors.grey[800],
                                              count: _post!.likesCount,
                                              onTap: _toggleLike,
                                            ),
                                            const SizedBox(width: 24),
                                            _buildActionButton(
                                              icon: Icons.chat_bubble_outline,
                                              color: Colors.grey[800],
                                              count: _post!.commentsCount,
                                              onTap: () {},
                                            ),
                                            const SizedBox(width: 24),
                                            _buildActionButton(
                                              icon: _post!.isShared ? Icons.close : Icons.repeat,
                                              color: _post!.isShared ? Colors.red : Colors.grey[800],
                                              count: _post!.sharesCount,
                                              onTap: () async {
                                                final originalShared = _post!.isShared;
                                                final originalCount = _post!.sharesCount;
                                                setState(() { 
                                                  _post!.isShared = !_post!.isShared;
                                                  if (_post!.isShared) {
                                                    _post!.sharesCount++;
                                                  } else {
                                                    _post!.sharesCount--;
                                                  }
                                                });
                                                final res = await ApiService.repostPost(_post!.id);
                                                if (res['success'] != true && mounted) {
                                                  setState(() { 
                                                    _post!.isShared = originalShared;
                                                    _post!.sharesCount = originalCount;
                                                  });
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 24),
                                            _buildActionButton(
                                              icon: _post!.isSaved ? Icons.bookmark : Icons.bookmark_border,
                                              color: _post!.isSaved ? Colors.amber : Colors.grey[800],
                                              count: _post!.savesCount,
                                              onTap: () async {
                                                final originalSaved = _post!.isSaved;
                                                final originalCount = _post!.savesCount;
                                                setState(() { 
                                                  _post!.isSaved = !_post!.isSaved;
                                                  if (_post!.isSaved) {
                                                    _post!.savesCount++;
                                                  } else {
                                                    _post!.savesCount--;
                                                  }
                                                });
                                                final res = await ApiService.savePost(_post!.id);
                                                if (res['success'] != true && mounted) {
                                                  setState(() { 
                                                    _post!.isSaved = originalSaved;
                                                    _post!.savesCount = originalCount;
                                                  });
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 24),
                                            _buildActionButton(
                                              icon: Icons.send_outlined,
                                              color: Colors.grey[800],
                                              count: 0,
                                              onTap: () {
                                                Share.share(" membagikan postingan:\n\n");
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(thickness: 1),
                            // COMMENTS LIST
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Text('Komentar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            if (_isLoadingComments)
                              const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (_comments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Center(child: Text('Belum ada komentar untuk postingan ini.')),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _comments.length,
                                itemBuilder: (context, index) {
                                  final c = _comments[index];
                                  final isMe = c['authorId'].toString() == _myUserId;
                                  return ListTile(
                                    leading: GestureDetector(
                                      onTap: () => _goToUserProfile(c['authorId'].toString()),
                                      child: CircleAvatar(
                                        backgroundColor: Colors.grey[300],
                                        child: Text(c['authorName'].toString().substring(0, 1).toUpperCase()),
                                      ),
                                    ),
                                    title: Text(c['authorName'].toString() + (isMe ? ' (Anda)' : ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: MentionParser.buildText(context, c['text'].toString(), myUserId: _myUserId),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    // COMMENT INPUT
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: SafeArea(
                        child: MentionInput(
                          controller: _commentController,
                          hintText: 'Tambahkan komentar...',
                          isSending: _isSending,
                          onSend: _sendComment,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
