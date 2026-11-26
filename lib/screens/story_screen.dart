import 'dart:io';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  List<UserStories> _unviewedStories = [];
  List<UserStories> _viewedStories = [];
  UserStories? _myStories;
  io.Socket? _socket;
  String? _myUserId;

  // Optimistic upload state (seperti WhatsApp)
  bool _isUploading = false;
  File? _uploadingFile;
  bool _uploadingIsVideo = false;
  String _uploadingCaption = '';
  double _uploadProgress = 0.0;
  bool _uploadFailed = false;

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
    final tokenRes =
        await ApiService.getCallsSocketToken(); // We can use the same token for auth
    if (!tokenRes['success']) return;

    final token = tokenRes['data']['token'];
    _socket = io.io(
      ApiService.chatSocketUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({
        'token': token,
      }).build(),
    );

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
            _unviewedStories = allStories
                .where((s) => !s.stories.every((story) => story.isViewed))
                .toList();
            _viewedStories = allStories
                .where((s) => s.stories.every((story) => story.isViewed))
                .toList();
          }
          if (myRes['success']) {
            final myRawStories = (myRes['data'] as List)
                .map((json) => Story.fromJson(json))
                .toList();
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
        });
      }
    } catch (e) {
      debugPrint('Error fetching stories: $e');
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
        builder: (context) =>
            const CustomGalleryPicker(showVideoTab: true, showTextTab: true),
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
          builder: (context) =>
              StoryPreviewScreen(file: result, isVideo: isVideo),
        ),
      );

      if (caption == null) return; // User cancelled

      if (!mounted) return;

      // Langsung tampilkan di "Status Saya" dengan animasi upload (seperti WA)
      setState(() {
        _isUploading = true;
        _uploadingFile = result;
        _uploadingIsVideo = isVideo;
        _uploadingCaption = caption as String;
        _uploadProgress = 0.0;
        _uploadFailed = false;
      });

      _startMediaUpload();
    }
  }

  void _startMediaUpload() async {
    if (_uploadingFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadFailed = false;
      _uploadProgress = 0.0;
    });

    try {
      final res = await ApiService.uploadMediaStory(
        _uploadingFile!.path,
        _uploadingCaption,
        onProgress: (progress) {
          if (mounted && _isUploading) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );

      if (!mounted) return;

      if (res['success'] == true) {
        setState(() {
          _isUploading = false;
          _uploadingFile = null;
          _uploadProgress = 0.0;
          _uploadFailed = false;
        });
        _fetchStories();
      } else {
        setState(() {
          _isUploading = false;
          _uploadFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengunggah status: ${res['message'] ?? 'Error'}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadFailed = true;
        });
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
                onChanged: (val) =>
                    setState(() => _searchQuery = val.toLowerCase()),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StoryPrivacyScreen()),
                );
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
                child: Text(
                  'Pembaruan terkini',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              ...filteredUnviewed.map((s) => _buildStoryTile(s)),
            ],
            if (filteredViewed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Pembaruan yang telah dilihat',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
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
    // 1. Tampilan saat SEDANG MENGUNGGAH (WhatsApp style)
    if (_isUploading && _uploadingFile != null) {
      final percentInt = (_uploadProgress * 100).toInt();
      return ListTile(
        leading: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Image.file(
                _uploadingFile!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.35),
              ),
            ),
            SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                strokeWidth: 3.5,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                backgroundColor: Colors.white24,
              ),
            ),
            if (_uploadingIsVideo)
              const Icon(Icons.videocam, color: Colors.white70, size: 18),
          ],
        ),
        title: const Text(
          'Status saya',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _uploadProgress > 0
              ? 'Mengunggah status ($percentInt%)...'
              : 'Mengunggah status...',
          style: const TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Text(
            '$percentInt%',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status sedang diunggah, mohon tunggu sebentar...'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      );
    }

    // 2. Tampilan saat GAGAL MENGUNGGAH (Bisa tap untuk coba lagi)
    if (_uploadFailed && _uploadingFile != null) {
      return ListTile(
        leading: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Image.file(
                _uploadingFile!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.5),
              ),
            ),
            const Icon(Icons.refresh, color: Colors.white, size: 24),
          ],
        ),
        title: const Text(
          'Status saya',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Gagal mengunggah. Ketuk untuk coba lagi',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          onPressed: () {
            setState(() {
              _uploadFailed = false;
              _uploadingFile = null;
            });
          },
        ),
        onTap: _startMediaUpload,
      );
    }

    // 3. Tampilan Normal
    final hasStory = _myStories != null && _myStories!.stories.isNotEmpty;

    Widget avatarContent;
    if (hasStory) {
      final firstStory = _myStories!.stories.first;
      if (firstStory.contentType == 'text') {
        avatarContent = CircleAvatar(
          radius: 25,
          backgroundColor: Colors.grey[300],
          child: Center(
            child: Text(
              firstStory.textContent?.substring(0, 1).toUpperCase() ?? 'S',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else if (firstStory.imageUrl != null && firstStory.imageUrl!.isNotEmpty) {
        final imgUrl = ApiService.getServerUrl(firstStory.imageUrl!);
        avatarContent = ClipOval(
          child: CachedNetworkImage(
            imageUrl: imgUrl,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[300]),
            errorWidget: (context, url, error) =>
                const Icon(Icons.person, color: Colors.white, size: 30),
          ),
        );
      } else if (firstStory.videoUrl != null && firstStory.videoUrl!.isNotEmpty) {
        avatarContent = const CircleAvatar(
          radius: 25,
          backgroundColor: Color(0xFF0F3460),
          child: Icon(Icons.videocam, color: Colors.white, size: 28),
        );
      } else {
        avatarContent = const CircleAvatar(
          radius: 25,
          backgroundColor: Colors.grey,
          child: Icon(Icons.person, color: Colors.white, size: 30),
        );
      }
    } else {
      avatarContent = const CircleAvatar(
        radius: 25,
        backgroundColor: Colors.grey,
        child: Icon(Icons.person, color: Colors.white, size: 30),
      );
    }

    Widget avatarWrapper = hasStory
        ? Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: avatarContent,
            ),
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
                decoration: const BoxDecoration(
                  color: Color(0xFF0F3460),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
      title: const Text(
        'Status saya',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        hasStory
            ? '${_myStories!.stories.length} pembaruan'
            : 'Ketuk untuk menambahkan pembaruan status',
      ),
      trailing: hasStory
          ? IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyStoriesScreen(myStories: _myStories!),
                  ),
                );
              },
            )
          : null,
      onTap: () {
        if (hasStory) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoryViewerScreen(userStories: _myStories!),
            ),
          );
        } else {
          _onAddCameraStatus();
        }
      },
    );
  }

  Widget _buildStoryTile(UserStories userStory) {
    final isAllViewed = userStory.stories.every((s) => s.isViewed);
    final hasCloseFriend = userStory.stories.any(
      (s) => s.privacyType == 'teman_dekat',
    );

    Widget avatarWrapper = CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey[300],
      child: Text(
        userStory.userName.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: Colors.black54,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (isAllViewed) {
      avatarWrapper = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: avatarWrapper,
        ),
      );
    } else if (hasCloseFriend) {
      avatarWrapper = Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [Colors.blue, Colors.lightBlueAccent, Colors.blue],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: avatarWrapper,
            ),
          ),
        ),
      );
    } else {
      avatarWrapper = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: avatarWrapper,
        ),
      );
    }

    return ListTile(
      leading: avatarWrapper,
      title: Text(
        userStory.userName,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('Hari ini'), // Ideally format the time
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoryViewerScreen(userStories: userStory),
          ),
        );
      },
    );
  }
}
