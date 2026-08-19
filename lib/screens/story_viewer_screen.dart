import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
// If using video, you might need video_player, but let's stick to simple implementation first
import '../models/story_model.dart';
import '../services/api_service.dart';

class StoryViewerScreen extends StatefulWidget {
  final UserStories userStories;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.userStories,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animController;
  int _currentIndex = 0;
  bool _isPaused = false;
  
  List<StoryViewer> _viewers = [];
  bool _isLoadingViewers = false;
  bool _isShowingViewers = false;
  double _verticalDragDelta = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // Default 5 seconds per story
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _loadStoryData();
  }

  void _loadStoryData() {
    _animController.forward(from: 0.0);
    _markAsViewed();
    _fetchViewers();
  }

  void _markAsViewed() async {
    final story = widget.userStories.stories[_currentIndex];
    // Don't mark our own stories as viewed
    if (widget.userStories.userName == 'Saya') return;
    
    // In a real app we pass the current user's data
    await ApiService.viewStory(story.id, {}); 
  }

  void _fetchViewers() async {
    final story = widget.userStories.stories[_currentIndex];
    if (widget.userStories.userName != 'Saya') return; // Only fetch viewers for own stories
    
    setState(() => _isLoadingViewers = true);
    final res = await ApiService.getStoryViewers(story.id);
    if (res['success'] && mounted) {
      setState(() {
        _viewers = (res['data'] as List).map((v) => StoryViewer.fromJson(v)).toList();
      });
    }
    if (mounted) setState(() => _isLoadingViewers = false);
  }

  void _nextStory() {
    if (_currentIndex < widget.userStories.stories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context); // End of stories
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  DateTime? _tapDownTime;

  void _onTapDown(TapDownDetails details) {
    if (_isShowingViewers) return;
    _tapDownTime = DateTime.now();
    _isPaused = true;
    _animController.stop();
  }

  void _onTapUp(TapUpDetails details) {
    if (_isShowingViewers) return;
    _isPaused = false;
    _animController.forward();
    
    if (_tapDownTime != null) {
      final duration = DateTime.now().difference(_tapDownTime!);
      if (duration.inMilliseconds < 300) {
        // Quick tap to navigate
        final screenWidth = MediaQuery.of(context).size.width;
        final dx = details.globalPosition.dx;
        
        if (dx < screenWidth / 3) {
          _previousStory();
        } else {
          _nextStory();
        }
      }
    }
  }

  void _onTapCancel() {
    if (_isShowingViewers) return;
    _isPaused = false;
    _animController.forward();
  }
  
  void _showViewersModal() {
    if (widget.userStories.userName != 'Saya') return;
    
    setState(() => _isShowingViewers = true);
    _animController.stop();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dilihat oleh ${_viewers.length}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: _isLoadingViewers
                    ? const Center(child: CircularProgressIndicator())
                    : _viewers.isEmpty
                        ? const Center(child: Text('Belum ada tayangan', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _viewers.length,
                            itemBuilder: (context, index) {
                              final v = _viewers[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.grey[300],
                                  child: const Icon(Icons.person, color: Colors.white),
                                ),
                                title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(v.phone ?? ''),
                                trailing: Text(
                                  _formatTime(v.viewedAt),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              );
                            },
                          ),
              )
            ],
          ),
        );
      }
    ).whenComplete(() {
      if (mounted) {
        setState(() => _isShowingViewers = false);
        _animController.forward();
      }
    });
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inHours < 1) return '${diff.inMinutes} menit yang lalu';
    if (diff.inDays < 1) return '${diff.inHours} jam yang lalu';
    return '${diff.inDays} hari yang lalu';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Widget _buildStoryContent(Story story) {
    if (story.contentType == 'text') {
      Color bgColor = Colors.black;
      if (story.backgroundColor != null && story.backgroundColor!.startsWith('#')) {
        try {
          bgColor = Color(int.parse(story.backgroundColor!.substring(1), radix: 16) + 0xFF000000);
        } catch (e) {
          // fallback
        }
      }
      return Container(
        color: bgColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              story.textContent ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    } else if (story.contentType == 'image') {
      final imageUrl = ApiService.getServerUrl(story.imageUrl!);
      return Container(
        color: Colors.black,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
          ),
        ),
      );
    } else {
      // fallback for video for now
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('Video belum didukung', style: TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.userStories.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onVerticalDragStart: (_) => _verticalDragDelta = 0,
        onVerticalDragUpdate: (details) {
          _verticalDragDelta += details.primaryDelta ?? 0;
        },
        onVerticalDragEnd: (details) {
          if (_verticalDragDelta < -30 && widget.userStories.userName == 'Saya') {
            if (!_isShowingViewers) _showViewersModal(); // Swipe up
          } else if (_verticalDragDelta > 30) {
            Navigator.pop(context); // Swipe down
          }
          _verticalDragDelta = 0;
        },
        child: Stack(
          children: [
            // PageView
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.userStories.stories.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                _loadStoryData();
              },
              itemBuilder: (context, index) {
                return _buildStoryContent(widget.userStories.stories[index]);
              },
            ),

            // Top Gradient & Info
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  children: [
                    // Progress Bars
                    Row(
                      children: List.generate(
                        widget.userStories.stories.length,
                        (index) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2.0),
                            child: AnimatedBuilder(
                              animation: _animController,
                              builder: (context, child) {
                                double value = 0.0;
                                if (index < _currentIndex) {
                                  value = 1.0;
                                } else if (index == _currentIndex) {
                                  value = _animController.value;
                                }
                                return LinearProgressIndicator(
                                  value: value,
                                  backgroundColor: Colors.white.withOpacity(0.3),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  minHeight: 2,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // User Info
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey,
                          child: Text(
                            widget.userStories.userName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.userStories.userName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                _formatTime(story.createdAt),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Caption or Swipe up indicator
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  children: [
                    if (story.contentType == 'image' && story.textContent != null && story.textContent!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20.0),
                        child: Text(
                          story.textContent!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    
                    if (widget.userStories.userName == 'Saya')
                      GestureDetector(
                        onTap: _showViewersModal,
                        child: Column(
                          children: [
                            const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                            Text(
                              _viewers.isNotEmpty ? '${_viewers.length} tayangan' : '0 tayangan',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
