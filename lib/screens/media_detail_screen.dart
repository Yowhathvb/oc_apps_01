import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../services/api_service.dart';

class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onDelete;

  const MediaDetailScreen({super.key, required this.post, this.onDelete});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    if (widget.post['media_type'] == 'video') {
      _initializeVideoPlayer();
    }
  }

  Future<void> _initializeVideoPlayer() async {
    final url = '${ApiService.baseUrl.replaceAll('/api', '')}${widget.post['media_url']}';
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();
    
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: true,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _deletePost() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Postingan'),
        content: const Text('Apakah Anda yakin ingin menghapus postingan ini secara permanen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeleting = true);
      final res = await ApiService.deleteMediaPost(widget.post['id']);
      setState(() => _isDeleting = false);
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Postingan berhasil dihapus')),
          );
          if (widget.onDelete != null) widget.onDelete!();
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal menghapus postingan')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.post['media_type'] == 'video';
    final mediaUrl = '${ApiService.baseUrl.replaceAll('/api', '')}${widget.post['media_url']}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Postingan'),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _isDeleting ? null : _deletePost,
            ),
        ],
      ),
      body: _isDeleting
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
              child: isVideo
                  ? (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized)
                      ? Chewie(controller: _chewieController!)
                      : const CircularProgressIndicator(color: Colors.white)
                  : InteractiveViewer(
                      child: Image.network(
                        mediaUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        },
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.white),
                      ),
                    ),
            ),
    );
  }
}
