import 'dart:io';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'custom_gallery_picker.dart';
import '../services/api_service.dart';
import '../models/story_model.dart';
import 'story_viewer_screen.dart';
import 'text_status_screen.dart';
import 'story_privacy_screen.dart';
import 'my_stories_screen.dart';
import 'story_preview_screen.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  bool _isLoading = true;
  List<UserStories> _unviewedStories = [];
  List<UserStories> _viewedStories = [];
  UserStories? _myStories;
  io.Socket? _socket;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getString('user_id');
    await _fetchStories();
    _initSocket();
  }

  void _initSocket() async {
    final tokenRes = await ApiService.getCallsSocketToken(); // We can use the same token for auth
    if (!tokenRes['success']) return;
    
    final token = tokenRes['data']['token'];
    _socket = io.io(ApiService.chatSocketUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .build());

    _socket?.onConnect((_) {
      _socket?.emit('subscribeRooms', _myUserId);
    });

    _socket?.on('story:update', (_) {
      _fetchStories();
    });
  }

  Future<void> _fetchStories() async {
    try {
      final res = await ApiService.getStories();
      final myRes = await ApiService.getMyStories();
      
      if (mounted) {
        setState(() {
          if (res['success']) {
            final allStories = (res['data'] as List)
                .map((json) => UserStories.fromJson(json))
                .where((s) => s.userId != _myUserId)
                .toList();
            _unviewedStories = allStories.where((s) => !s.stories.every((story) => story.isViewed)).toList();
            _viewedStories = allStories.where((s) => s.stories.every((story) => story.isViewed)).toList();
          }
          if (myRes['success']) {
            final myRawStories = (myRes['data'] as List).map((json) => Story.fromJson(json)).toList();
            if (myRawStories.isNotEmpty) {
              _myStories = UserStories(
                userId: _myUserId ?? '',
                userName: 'Saya',
                stories: myRawStories,
              );
            } else {
              _myStories = null;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stories: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  void _onAddTextStatus() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TextStatusScreen()),
    );
    if (result == true) {
      _fetchStories();
    }
  }

  void _onAddCameraStatus() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomGalleryPicker(
          showVideoTab: true,
          showTextTab: true,
        ),
      ),
    );

    if (result == 'text') {
      _onAddTextStatus();
      return;
    }

    if (result != null && result is File) {
      if (!mounted) return;
      
      final isVideo = result.path.toLowerCase().endsWith('.mp4');
      final caption = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StoryPreviewScreen(
            file: result,
            isVideo: isVideo,
          ),
        ),
      );

      if (caption == null) return; // User cancelled

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mengunggah status...')),
      );
      
      final res = await ApiService.uploadMediaStory(result.path, caption as String);
      if (res['success']) {
        _fetchStories();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${res['message']}')),
        );
      }
    }
  }

  bool _isSearching = false;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    
    final filteredUnviewed = _unviewedStories
        .where((s) => s.userName.toLowerCase().contains(_searchQuery))
        .toList();
    final filteredViewed = _viewedStories
        .where((s) => s.userName.toLowerCase().contains(_searchQuery))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Cari...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              )
            : const Text('Status'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchQuery = '';
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'privacy') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StoryPrivacyScreen()));
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'privacy',
                  child: Text('Privasi status'),
                ),
              ];
            },
          ),
        ],
      ),
      body: RefreshIndicator(
              onRefresh: _fetchStories,
              child: ListView(
                children: [
                  if (!_isSearching) _buildMyStatusTile(),
                  if (filteredUnviewed.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('Pembaruan terkini', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    ...filteredUnviewed.map((s) => _buildStoryTile(s)),
                  ],
                  if (filteredViewed.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('Pembaruan yang telah dilihat', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    ...filteredViewed.map((s) => _buildStoryTile(s)),
                  ],
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn_text",
            mini: true,
            backgroundColor: Colors.grey[200],
            foregroundColor: Colors.black87,
            onPressed: _onAddTextStatus,
            child: const Icon(Icons.edit),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "btn_camera",
            backgroundColor: primaryColor,
            onPressed: _onAddCameraStatus,
            child: const Icon(Icons.camera_alt),
          ),
        ],
      ),
    );
  }

  Widget _buildMyStatusTile() {
    final hasStory = _myStories != null && _myStories!.stories.isNotEmpty;
    
    Widget avatarContent = CircleAvatar(
      radius: 25,
      backgroundColor: Colors.grey[300],
      child: hasStory && _myStories!.stories.first.contentType == 'text'
          ? Center(
              child: Text(
                _myStories!.stories.first.textContent?.substring(0, 1).toUpperCase() ?? 'S',
                style: const TextStyle(color: Colors.black54, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            )
          : const Icon(Icons.person, color: Colors.white, size: 30),
    );

    Widget avatarWrapper = hasStory 
      ? Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: Padding(padding: const EdgeInsets.all(2.0), child: avatarContent),
        )
      : avatarContent;

    return ListTile(
      leading: Stack(
        children: [
          avatarWrapper,
          if (!hasStory)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFF0F3460), shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            )
        ],
      ),
      title: const Text('Status saya', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(hasStory ? '${_myStories!.stories.length} pembaruan' : 'Ketuk untuk menambahkan pembaruan status'),
      trailing: hasStory ? IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => MyStoriesScreen(myStories: _myStories!)));
        },
      ) : null,
      onTap: () {
        if (hasStory) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => StoryViewerScreen(userStories: _myStories!)));
        } else {
          _onAddCameraStatus();
        }
      },
    );
  }

  Widget _buildStoryTile(UserStories userStory) {
    final isAllViewed = userStory.stories.every((s) => s.isViewed);
    final hasCloseFriend = userStory.stories.any((s) => s.privacyType == 'teman_dekat');

    Widget avatarWrapper = CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey[300],
      child: Text(
        userStory.userName.substring(0, 1).toUpperCase(),
        style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
      ),
    );

    if (isAllViewed) {
      avatarWrapper = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey, width: 2),
        ),
        child: Padding(padding: const EdgeInsets.all(2.0), child: avatarWrapper),
      );
    } else if (hasCloseFriend) {
      avatarWrapper = Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [Colors.blue, Colors.lightBlueAccent, Colors.blue]),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: Padding(padding: const EdgeInsets.all(2.0), child: avatarWrapper),
          ),
        ),
      );
    } else {
      avatarWrapper = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: Padding(padding: const EdgeInsets.all(2.0), child: avatarWrapper),
      );
    }

    return ListTile(
      leading: avatarWrapper,
      title: Text(userStory.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('Hari ini'), // Ideally format the time
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => StoryViewerScreen(userStories: userStory)));
      },
    );
  }
}
