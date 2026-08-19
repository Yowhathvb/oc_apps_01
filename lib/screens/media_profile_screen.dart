import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'follows_list_screen.dart';
import '../widgets/profile_tabs.dart';

class MediaProfileScreen extends StatefulWidget {
  const MediaProfileScreen({super.key});

  @override
  State<MediaProfileScreen> createState() => _MediaProfileScreenState();
}

class _MediaProfileScreenState extends State<MediaProfileScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final res = await ApiService.getMyProfile();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _profileData = res['data']['user'];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Media', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profileData == null
              ? const Center(child: Text('Gagal memuat profil'))
              : _buildProfileContent(primaryColor),
    );
  }

  Widget _buildProfileContent(Color primaryColor) {
    return NestedScrollView(
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
          ProfilePostsTab(userId: _profileData!['id'].toString(), contentType: 'posts'),
          ProfileReelsTab(userId: _profileData!['id'].toString(), contentType: 'reels'),
          ProfileRepostsTab(userId: _profileData!['id'].toString()),
          ProfilePostsTab(userId: _profileData!['id'].toString(), contentType: 'likes'),
          ProfilePostsTab(userId: _profileData!['id'].toString(), contentType: 'saved'),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Avatar
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.grey[300],
            backgroundImage: _profileData?['avatar'] != null
                ? NetworkImage(ApiService.getServerUrl(_profileData!['avatar']))
                : null,
            child: _profileData?['avatar'] == null
                ? Text(
                    (_profileData?['name'] ?? 'U').substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.black54),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          // Name
          Text(
            _profileData!['name'],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          // Username
          Text(
            '@${_profileData!['username']}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          if (_profileData!['bio'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _profileData!['bio'],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
          const SizedBox(height: 16),
          
          // Action Buttons (Moved under username/bio)
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edit profil belum tersedia')));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Edit Profil', style: TextStyle(color: Colors.white)),
          ),
          
          const SizedBox(height: 20),
          
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
                _buildStatItem('Postingan', _profileData!['posts_count'], null),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                _buildStatItem('Pengikut', _profileData!['followers_count'], () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FollowsListScreen(userId: _profileData!['id'].toString(), mode: 'followers')));
                }),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                _buildStatItem('Mengikuti', _profileData!['following_count'], () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FollowsListScreen(userId: _profileData!['id'].toString(), mode: 'following')));
                }),
              ],
            ),
          ),
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
  final TabBar _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
