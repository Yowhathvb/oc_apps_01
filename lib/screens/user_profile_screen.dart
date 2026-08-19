import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'follows_list_screen.dart';
import '../models/post_model.dart';
import '../widgets/profile_tabs.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _userProfile;
  List<PostModel> _posts = [];
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getUserProfile(widget.userId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _userProfile = res['data'];
          _isFollowing = _userProfile?['isFollowing'] == 1 || _userProfile?['isFollowing'] == true;
          
          final List postsData = _userProfile?['posts'] ?? [];
          _posts = postsData.map((json) => PostModel.fromJson(json)).toList();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal memuat profil')),
          );
        }
      });
    }
  }

  Future<void> _toggleFollow() async {
    final originalState = _isFollowing;
    setState(() {
      _isFollowing = !_isFollowing;
    });

    final res = await ApiService.toggleFollow(widget.userId);
    if (res['success'] != true) {
      if (mounted) {
        setState(() {
          _isFollowing = originalState;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengikuti/batal mengikuti')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isFollowing ? 'Berhasil mengikuti' : 'Berhasil berhenti mengikuti')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: Text(_userProfile?['username'] ?? 'Profil'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userProfile == null
              ? const Center(child: Text("Pengguna tidak ditemukan"))
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: _buildProfileHeader(primaryColor),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverAppBarDelegate(
                          TabBar(
                            controller: _tabController,
                            labelColor: primaryColor,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: primaryColor,
                            tabs: const [
                              Tab(icon: Icon(Icons.grid_on)),
                              Tab(icon: Icon(Icons.video_library)),
                              Tab(icon: Icon(Icons.repeat)),
                              Tab(icon: Icon(Icons.favorite_border)),
                              Tab(icon: Icon(Icons.bookmark_border)),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      ProfilePostsTab(userId: widget.userId, contentType: 'posts'),
                      ProfileReelsTab(userId: widget.userId, contentType: 'reels'),
                      ProfileRepostsTab(userId: widget.userId),
                      ProfilePostsTab(userId: widget.userId, contentType: 'likes'),
                      ProfilePostsTab(userId: widget.userId, contentType: 'saved'),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileHeader(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[300],
                backgroundImage: _userProfile?['avatar'] != null
                    ? NetworkImage(ApiService.getServerUrl(_userProfile!['avatar']))
                    : null,
                child: _userProfile?['avatar'] == null
                    ? Text(
                        (_userProfile?['name'] ?? 'U').substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.black54),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userProfile?['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    Text(
                      _userProfile?['username'] != null ? '@${_userProfile!['username']}' : '',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_userProfile?['bio'] != null && _userProfile!['bio'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(_userProfile!['bio'], style: const TextStyle(fontSize: 14)),
            ),
            
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFollowing ? Colors.grey[300] : primaryColor,
                    foregroundColor: _isFollowing ? Colors.black : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_isFollowing ? 'Mengikuti' : 'Ikuti'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats Row with borders
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('Postingan', _userProfile?['posts_count'] ?? 0, null),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                _buildStatItem('Pengikut', _userProfile?['followers_count'] ?? 0, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FollowsListScreen(userId: widget.userId, mode: 'followers')));
                }),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                _buildStatItem('Mengikuti', _userProfile?['following_count'] ?? 0, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FollowsListScreen(userId: widget.userId, mode: 'following')));
                }),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, dynamic value, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
