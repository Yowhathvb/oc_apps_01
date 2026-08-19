import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'user_profile_screen.dart';

class FollowsListScreen extends StatefulWidget {
  final String userId;
  final String mode; // 'followers' or 'following'

  const FollowsListScreen({super.key, required this.userId, required this.mode});

  @override
  State<FollowsListScreen> createState() => _FollowsListScreenState();
}

class _FollowsListScreenState extends State<FollowsListScreen> {
  bool _isLoading = true;
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getFollows(widget.userId, widget.mode);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _users = res['data'];
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal memuat data')),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == 'followers' ? 'Pengikut' : 'Mengikuti', style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(child: Text(widget.mode == 'followers' ? 'Belum ada pengikut' : 'Belum mengikuti siapapun'))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[300],
                        backgroundImage: user['avatar'] != null ? NetworkImage(ApiService.getServerUrl(user['avatar'])) : null,
                        child: user['avatar'] == null ? Text(user['name'].toString().substring(0, 1).toUpperCase()) : null,
                      ),
                      title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('@${user['username']}'),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => UserProfileScreen(userId: user['id'].toString())),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
