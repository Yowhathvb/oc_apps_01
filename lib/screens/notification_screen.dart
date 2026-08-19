import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'single_post_screen.dart';
import 'user_profile_screen.dart';
import 'media_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    _fetchNotifications();
    ApiService.markNotificationsRead();
  }

  Future<void> _loadMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUserId = prefs.getString('user_id');
    });
  }

  Future<void> _fetchNotifications() async {
    final res = await ApiService.getNotifications();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _notifications = res['data'];
        }
      });
    }
  }

  void _goToUserProfile(String? userId) {
    if (userId == null) return;
    if (userId == _myUserId) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaProfileScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
    }
  }

  void _goToPost(int? postId) {
    if (postId == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SinglePostScreen(postId: postId)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('Belum ada notifikasi.'))
              : ListView.separated(
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.transparent),
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    final isUnread = notif['is_read'] == 0 || notif['is_read'] == false;
                    
                    final senderAvatar = notif['sender_avatar'];
                    final senderName = notif['sender_name'] ?? 'Seseorang';
                    final senderIdStr = notif['sender_id']?.toString();
                    
                    final postMediaUrl = notif['post_media_url'];
                    final isPostRelated = notif['type'] == 'like' || notif['type'] == 'comment' || notif['type'] == 'mention';
                    
                    return InkWell(
                      onTap: () {
                        if (isPostRelated) {
                          _goToPost(notif['reference_id']);
                        } else if (notif['type'] == 'follow') {
                          _goToUserProfile(senderIdStr ?? notif['reference_id']?.toString());
                        }
                      },
                      child: Container(
                        color: isUnread ? Colors.blue.withOpacity(0.05) : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Avatar
                            GestureDetector(
                              onTap: () => _goToUserProfile(senderIdStr),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.grey[300],
                                backgroundImage: senderAvatar != null
                                    ? NetworkImage(ApiService.getServerUrl(senderAvatar))
                                    : null,
                                child: senderAvatar == null
                                    ? Text(
                                        senderName.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Message Content
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: Colors.black, fontSize: 14),
                                  children: [
                                    TextSpan(
                                      text: " ",
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    TextSpan(
                                      text: " " + notif['message'].toString().replaceAll(senderName, "").trim(),
                                    ),
                                    if (isPostRelated && notif['post_caption'] != null && notif['post_caption'].toString().isNotEmpty)
                                      TextSpan(
                                        text: " : """,
                                        style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black87),
                                      ),
                                    TextSpan(
                                      text: "  ",
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Trailing Thumbnail (Post Image or Follow Button)
                            if (isPostRelated && postMediaUrl != null)
                              GestureDetector(
                                onTap: () => _goToPost(notif['reference_id']),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    ApiService.getServerUrl(postMediaUrl),
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 44,
                                      height: 44,
                                      color: Colors.grey[200],
                                      child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
