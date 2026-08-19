import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/post_model.dart';
import 'package:timeago/timeago.dart' as timeago;

class ProfilePostsTab extends StatefulWidget {
  final String userId;
  final String contentType;

  const ProfilePostsTab({super.key, required this.userId, required this.contentType});

  @override
  State<ProfilePostsTab> createState() => _ProfilePostsTabState();
}

class _ProfilePostsTabState extends State<ProfilePostsTab> {
  bool _isLoading = true;
  List<PostModel> _posts = [];

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    final res = await ApiService.getUserContent(widget.userId, widget.contentType);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _posts = (res['data'] as List).map((p) => PostModel.fromJson(p)).toList();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return Center(child: Text(widget.contentType == 'likes' ? 'Belum ada yang disukai' : 'Belum ada postingan'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _posts.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: post.authorAvatar != null
                        ? NetworkImage(ApiService.getServerUrl(post.authorAvatar!))
                        : null,
                    child: post.authorAvatar == null ? Text(post.authorName.substring(0,1).toUpperCase(), style: const TextStyle(fontSize: 12)) : null,
                  ),
                  const SizedBox(width: 8),
                  Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text("• ${timeago.format(post.createdAt, locale: 'id')}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              if (post.caption.isNotEmpty) Text(post.caption),
              if (post.mediaUrl != null && post.mediaType == 'image') ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    ApiService.getServerUrl(post.mediaUrl!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 200,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ProfileReelsTab extends StatefulWidget {
  final String userId;
  final String contentType;

  const ProfileReelsTab({super.key, required this.userId, required this.contentType});

  @override
  State<ProfileReelsTab> createState() => _ProfileReelsTabState();
}

class _ProfileReelsTabState extends State<ProfileReelsTab> {
  bool _isLoading = true;
  List<PostModel> _reels = [];

  @override
  void initState() {
    super.initState();
    _fetchReels();
  }

  Future<void> _fetchReels() async {
    final res = await ApiService.getUserContent(widget.userId, widget.contentType);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _reels = (res['data'] as List).map((p) => PostModel.fromJson(p)).toList();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reels.isEmpty) {
      return const Center(child: Text("Belum ada Reels"));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _reels.length,
      itemBuilder: (context, index) {
        final reel = _reels[index];
        return Container(
          color: Colors.grey[800],
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Placeholder for video thumbnail. 
              // Usually we'd use Image.network if we have a thumbnail URL.
              // For now, just a dark background with an icon.
              const Center(
                child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ProfileRepostsTab extends StatefulWidget {
  final String userId;

  const ProfileRepostsTab({super.key, required this.userId});

  @override
  State<ProfileRepostsTab> createState() => _ProfileRepostsTabState();
}

class _ProfileRepostsTabState extends State<ProfileRepostsTab> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: primaryColor,
          tabs: const [
            Tab(text: "Postingan"),
            Tab(text: "Reels"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              ProfilePostsTab(userId: widget.userId, contentType: 'reposts_posts'),
              ProfileReelsTab(userId: widget.userId, contentType: 'reposts_reels'),
            ],
          ),
        ),
      ],
    );
  }
}
