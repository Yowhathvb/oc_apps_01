import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../widgets/video_trimmer_panel.dart';
import 'custom_gallery_picker.dart';

class CreatePostScreen extends StatefulWidget {
  final bool initialVideoMode;

  const CreatePostScreen({super.key, this.initialVideoMode = false});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxVideoBytes = 100 * 1024 * 1024; // 100 MB
  static const int _maxVideoSeconds = 90; // 1.5 menit
  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.webm',
    '.mkv',
    '.avi',
    '.m4v',
    '.3gp',
  };

  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  File? _selectedFile;
  bool _isVideo = false;
  bool _isAudio = false;
  AudioPlayer? _audioPreviewPlayer;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  StreamSubscription? _audioStateSub;
  StreamSubscription? _audioPosSub;
  StreamSubscription? _audioDurSub;
  StreamSubscription? _audioCompSub;

  Map<String, dynamic>? _selectedPoll;
  VideoPlayerController? _videoPreviewController;
  Duration? _videoDuration;
  double _trimStart = 0.0;
  double _trimEnd = 0.0;
  double _previewPositionSec = 0.0;
  int? _fileSizeBytes;
  String? _validationError;

  bool _isCheckingMedia = false;
  bool _isUploading = false;
  bool _canPost = false;

  @override
  void initState() {
    super.initState();
    _captionController.addListener(_updateCanPost);
    if (widget.initialVideoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showVideoSourcePicker();
      });
    }
  }

  @override
  void dispose() {
    _captionController.removeListener(_updateCanPost);
    _captionController.dispose();
    _videoPreviewController?.removeListener(_onVideoPreviewTick);
    _videoPreviewController?.dispose();
    _disposeAudioPreview();
    super.dispose();
  }

  void _initAudioPreview(File file) {
    _disposeAudioPreview();
    final player = AudioPlayer();
    _audioPreviewPlayer = player;
    _audioPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _isAudioPlaying = false;

    _audioStateSub = player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioDurSub = player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _audioDuration = dur;
        });
      }
    });

    _audioPosSub = player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _audioPosition = pos;
        });
      }
    });

    _audioCompSub = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
          _audioPosition = Duration.zero;
        });
      }
    });
  }

  void _disposeAudioPreview() {
    _audioStateSub?.cancel();
    _audioPosSub?.cancel();
    _audioDurSub?.cancel();
    _audioCompSub?.cancel();
    _audioPreviewPlayer?.stop();
    _audioPreviewPlayer?.dispose();
    _audioPreviewPlayer = null;
    _isAudioPlaying = false;
    _audioPosition = Duration.zero;
    _audioDuration = Duration.zero;
  }

  Future<void> _toggleAudioPreview() async {
    final player = _audioPreviewPlayer;
    if (player == null || _selectedFile == null) return;
    try {
      if (_isAudioPlaying) {
        await player.pause();
      } else {
        if (_audioPosition > Duration.zero && _audioPosition < _audioDuration) {
          await player.resume();
        } else {
          await player.play(DeviceFileSource(_selectedFile!.path));
        }
      }
    } catch (e) {
      debugPrint('[CreatePostScreen] Audio preview error: $e');
    }
  }

  String _formatAudioDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onVideoPreviewTick() {
    final controller = _videoPreviewController;
    if (controller == null || !mounted || !controller.value.isInitialized)
      return;
    final posSec = controller.value.position.inMilliseconds / 1000.0;
    final hasClipRange = _trimEnd > _trimStart && _videoDuration != null;
    if (hasClipRange && controller.value.isPlaying && posSec >= _trimEnd) {
      controller.pause();
      controller.seekTo(Duration(milliseconds: (_trimStart * 1000).round()));
      setState(() => _previewPositionSec = _trimStart);
      return;
    }
    if ((posSec - _previewPositionSec).abs() >= 0.1 ||
        controller.value.isPlaying) {
      setState(() => _previewPositionSec = posSec);
    }
  }

  void _updateCanPost() {
    final hasValidMedia = _selectedFile != null && _validationError == null;
    final hasText = _captionController.text.trim().isNotEmpty;
    final hasPoll = _selectedPoll != null;
    setState(() {
      _canPost = hasValidMedia || hasText || hasPoll;
    });
  }

  bool _looksLikeVideo(String path) {
    final lower = path.toLowerCase();
    return _videoExtensions.any((ext) => lower.endsWith(ext));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDuration(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return m > 0 ? '${m}m ${s}d' : '$s detik';
  }

  Future<void> _handlePickedFile(File file, {bool forceVideo = false}) async {
    setState(() {
      _isCheckingMedia = true;
      _validationError = null;
    });

    _videoPreviewController?.removeListener(_onVideoPreviewTick);
    await _videoPreviewController?.dispose();
    _videoPreviewController = null;
    _videoDuration = null;
    _trimStart = 0.0;
    _trimEnd = 0.0;
    _previewPositionSec = 0.0;

    final isVideo = forceVideo || _looksLikeVideo(file.path);
    final fileSize = await file.length();

    if (fileSize > _maxVideoBytes) {
      if (!mounted) return;
      setState(() {
        _isCheckingMedia = false;
        _selectedFile = null;
        _isVideo = false;
        _fileSizeBytes = null;
        _validationError =
            'Ukuran file (${_formatBytes(fileSize)}) melebihi batas maksimal 100 MB';
      });
      _updateCanPost();
      return;
    }

    if (isVideo) {
      final controller = VideoPlayerController.file(file);
      try {
        await controller.initialize();
        final duration = controller.value.duration;
        final totalSeconds = duration.inMilliseconds / 1000.0;
        final initialEnd = totalSeconds > 0
            ? math.min(totalSeconds, _maxVideoSeconds.toDouble())
            : 0.0;
        await controller.setLooping(false);
        controller.addListener(_onVideoPreviewTick);
        if (!mounted) {
          controller.removeListener(_onVideoPreviewTick);
          await controller.dispose();
          return;
        }
        setState(() {
          _isCheckingMedia = false;
          _selectedFile = file;
          _isVideo = true;
          _fileSizeBytes = fileSize;
          _videoDuration = duration;
          _trimStart = 0.0;
          _trimEnd = (initialEnd * 10).roundToDouble() / 10;
          _previewPositionSec = 0.0;
          _videoPreviewController = controller;
        });
        _updateCanPost();
      } catch (_) {
        await controller.dispose();
        if (!mounted) return;
        // Let server validate with ffprobe if local codec preview fails
        setState(() {
          _isCheckingMedia = false;
          _selectedFile = file;
          _isVideo = true;
          _fileSizeBytes = fileSize;
          _videoDuration = null;
          _videoPreviewController = null;
        });
        _updateCanPost();
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isCheckingMedia = false;
      _selectedFile = file;
      _isVideo = false;
      _fileSizeBytes = fileSize;
    });
    _updateCanPost();
  }

  Future<void> _pickMedia({bool videoMode = false}) async {
    final pickedFile = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CustomGalleryPicker(
              showVideoTab: true,
              initialTab: videoMode ? 'video' : 'foto',
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutQuart;
          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
    if (pickedFile != null && pickedFile is File) {
      await _handlePickedFile(pickedFile);
    }
  }

  void _showVideoSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'Upload Video (Maks 1,5 Menit & 100 MB)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Video lebih dari 1,5 menit bisa dipotong langsung sebelum diunggah (maks ukuran file 100 MB)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFF0F3460),
              ),
              title: const Text('Pilih Video dari Galeri'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _imagePicker.pickVideo(
                  source: ImageSource.gallery,
                );
                if (picked != null && mounted) {
                  await _handlePickedFile(File(picked.path), forceVideo: true);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.videocam_outlined,
                color: Color(0xFF0F3460),
              ),
              title: const Text('Rekam / Buka Kamera Video'),
              onTap: () {
                Navigator.pop(ctx);
                _pickMedia(videoMode: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _clearSelectedMedia() {
    _videoPreviewController?.removeListener(_onVideoPreviewTick);
    _videoPreviewController?.dispose();
    _disposeAudioPreview();
    setState(() {
      _videoPreviewController = null;
      _selectedFile = null;
      _isVideo = false;
      _isAudio = false;
      _videoDuration = null;
      _trimStart = 0.0;
      _trimEnd = 0.0;
      _previewPositionSec = 0.0;
      _fileSizeBytes = null;
      _validationError = null;
    });
    _updateCanPost();
  }

  Future<void> _togglePreviewTrim() async {
    final controller = _videoPreviewController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      final posSec = controller.value.position.inMilliseconds / 1000.0;
      if (_trimEnd > _trimStart &&
          (posSec < _trimStart || posSec >= _trimEnd - 0.1)) {
        await controller.seekTo(
          Duration(milliseconds: (_trimStart * 1000).round()),
        );
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _uploadPost() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty && _selectedFile == null) return;

    final totalSeconds = (_videoDuration?.inMilliseconds ?? 0) / 1000.0;
    final hasClipSelection = _trimEnd > _trimStart && totalSeconds > 0;
    final shouldSendTrim =
        _isVideo &&
        hasClipSelection &&
        (totalSeconds > _maxVideoSeconds ||
            _trimStart > 0.05 ||
            _trimEnd < totalSeconds - 0.15);

    if (shouldSendTrim && (_trimEnd - _trimStart) > _maxVideoSeconds + 0.05) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Durasi potongan video tidak boleh melebihi 1,5 menit (90 detik)',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    final Map<String, dynamic> res;
    if (_selectedFile != null && _isVideo) {
      res = await ApiService.uploadVideoPost(
        caption,
        _selectedFile!.path,
        trimStart: shouldSendTrim ? _trimStart : null,
        trimEnd: shouldSendTrim ? _trimEnd : null,
      );
    } else {
      final pollJson = _selectedPoll != null ? jsonEncode(_selectedPoll) : null;
      res = await ApiService.uploadPost(
        caption,
        _selectedFile?.path,
        poll: pollJson,
      );
    }

    if (!mounted) return;
    setState(() {
      _isUploading = false;
    });

    if (res['success'] == true) {
      if (_isVideo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video berhasil diunggah ke Our Media')),
        );
      } else if (_isAudio) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio / Musik berhasil diunggah ke Our Media'),
          ),
        );
      }
      Navigator.pop(context, _isVideo ? 'video' : true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Gagal mengunggah'),
        ),
      );
    }
  }

  Future<void> _pickGif() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif', 'mp4'],
      );
      if (res != null && res.files.single.path != null) {
        final file = File(res.files.single.path!);
        final pathLower = file.path.toLowerCase();

        if (pathLower.endsWith('.mp4')) {
          setState(() {
            _isCheckingMedia = true;
          });
          final tempController = VideoPlayerController.file(file);
          try {
            await tempController.initialize();
            final durSec =
                tempController.value.duration.inMilliseconds / 1000.0;
            await tempController.dispose();

            if (durSec > 5.15) {
              if (!mounted) return;
              setState(() {
                _isCheckingMedia = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Video untuk GIF harus berdurasi maksimal 5 detik (video ini ${durSec.toStringAsFixed(1)} detik)',
                  ),
                  backgroundColor: Colors.orange.shade800,
                ),
              );
              return;
            }
          } catch (err) {
            await tempController.dispose();
            debugPrint('Error checking mp4 duration: $err');
          }
          await _handlePickedFile(file, forceVideo: true);
        } else {
          await _handlePickedFile(file);
        }
      }
    } catch (e) {
      debugPrint('Error pick GIF: $e');
    }
  }

  Future<void> _pickAudio() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'opus'],
      );
      if (res != null && res.files.single.path != null) {
        final file = File(res.files.single.path!);
        final bytes = await file.length();
        _clearSelectedMedia();
        setState(() {
          _selectedFile = file;
          _isAudio = true;
          _isVideo = false;
          _fileSizeBytes = bytes;
          _validationError = null;
        });
        _initAudioPreview(file);
        _updateCanPost();
      }
    } catch (e) {
      debugPrint('Error pick audio: $e');
    }
  }

  void _showCreatePollDialog() {
    final questionCtrl = TextEditingController();
    final optionCtrls = [TextEditingController(), TextEditingController()];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.poll_outlined, color: Color(0xFF0F3460)),
                  SizedBox(width: 8),
                  Text(
                    'Buat Polling',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: questionCtrl,
                      decoration: InputDecoration(
                        labelText: 'Pertanyaan Polling',
                        hintText: 'Ajukan pertanyaan...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Pilihan Jawaban:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(optionCtrls.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: optionCtrls[i],
                                decoration: InputDecoration(
                                  labelText: 'Pilihan ${i + 1}',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            if (optionCtrls.length > 2)
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    optionCtrls.removeAt(i);
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                    if (optionCtrls.length < 5)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tambah Pilihan'),
                        onPressed: () {
                          setDialogState(() {
                            optionCtrls.add(TextEditingController());
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Batal',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F3460),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    final q = questionCtrl.text.trim();
                    final validOptions = optionCtrls
                        .map((c) => c.text.trim())
                        .where((t) => t.isNotEmpty)
                        .toList();
                    if (q.isEmpty || validOptions.length < 2) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Masukkan pertanyaan dan minimal 2 pilihan',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx);

                    setState(() {
                      _selectedPoll = {
                        'question': q,
                        'options': validOptions,
                        'multiple_answers': false,
                      };
                    });
                    _updateCanPost();
                  },
                  child: const Text(
                    'Terapkan',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Postingan Our Media',
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Anda',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          TextField(
                            controller: _captionController,
                            maxLines: null,
                            decoration: const InputDecoration(
                              hintText:
                                  'Tulis cerita atau caption video untuk Our Media...',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                          ),
                          if (_validationError != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade700,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _validationError!,
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_isCheckingMedia) ...[
                            const SizedBox(height: 12),
                            const Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Memeriksa ukuran & durasi media...',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          if (_selectedPoll != null) ...[
                            Container(
                              margin: const EdgeInsets.only(top: 8, bottom: 12),

                              padding: const EdgeInsets.all(12),

                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),

                                borderRadius: BorderRadius.circular(5),

                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                ),
                              ),

                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.poll_rounded,
                                        color: Color(0xFF0F3460),
                                        size: 20,
                                      ),

                                      const SizedBox(width: 8),

                                      Expanded(
                                        child: Text(
                                          _selectedPoll!['question']
                                                  ?.toString() ??
                                              'Polling',

                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),

                                      InkWell(
                                        onTap: () {
                                          setState(() => _selectedPoll = null);

                                          _updateCanPost();
                                        },

                                        borderRadius: BorderRadius.circular(5),

                                        child: const Padding(
                                          padding: EdgeInsets.all(4),

                                          child: Icon(
                                            Icons.close,
                                            size: 18,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  ...((_selectedPoll!['options']
                                              as List<dynamic>? ??
                                          [])
                                      .map(
                                        (opt) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),

                                          child: Container(
                                            width: double.infinity,

                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),

                                            decoration: BoxDecoration(
                                              color: Colors.white,

                                              borderRadius:
                                                  BorderRadius.circular(5),

                                              border: Border.all(
                                                color: const Color(0xFFE2E8F0),
                                              ),
                                            ),

                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.radio_button_off,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),

                                                const SizedBox(width: 8),

                                                Expanded(
                                                  child: Text(
                                                    opt.toString(),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          ],

                          if (_selectedPoll != null) ...[
                            Container(
                              margin: const EdgeInsets.only(top: 8, bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.poll_rounded,
                                        color: Color(0xFF0F3460),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _selectedPoll!['question']
                                                  ?.toString() ??
                                              'Polling',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          setState(() => _selectedPoll = null);
                                          _updateCanPost();
                                        },
                                        borderRadius: BorderRadius.circular(5),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.close,
                                            size: 18,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...((_selectedPoll!['options']
                                              as List<dynamic>? ??
                                          [])
                                      .map(
                                        (opt) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.radio_button_off,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    opt.toString(),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          ],
                          if (_selectedFile != null && !_isVideo && !_isAudio)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    _selectedFile!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: _clearSelectedMedia,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_selectedFile != null && _isAudio)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1E293B),
                                    Color(0xFF0F172A),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.white12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF3B82F6),
                                              Color(0xFF1D4ED8),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _selectedFile!.path
                                                  .split(Platform.pathSeparator)
                                                  .last,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_isAudioPlaying ? 'Memutar pratinjau' : 'File Audio'} • ${_fileSizeBytes != null ? (_fileSizeBytes! / (1024 * 1024)).toStringAsFixed(2) : '0'} MB',
                                              style: TextStyle(
                                                color: _isAudioPlaying
                                                    ? Colors.greenAccent
                                                    : Colors.white60,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: _toggleAudioPreview,
                                        iconSize: 36,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(
                                          _isAudioPlaying
                                              ? Icons
                                                    .pause_circle_filled_rounded
                                              : Icons.play_circle_fill_rounded,
                                          color: const Color(0xFF38BDF8),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white60,
                                          size: 20,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: _clearSelectedMedia,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 10,
                                          ),
                                      activeTrackColor: const Color(0xFF38BDF8),
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: Colors.white,
                                    ),
                                    child: Slider(
                                      value: _audioPosition.inMilliseconds
                                          .toDouble()
                                          .clamp(
                                            0.0,
                                            _audioDuration.inMilliseconds
                                                        .toDouble() >
                                                    0
                                                ? _audioDuration.inMilliseconds
                                                      .toDouble()
                                                : 1.0,
                                          ),
                                      min: 0.0,
                                      max:
                                          _audioDuration.inMilliseconds
                                                  .toDouble() >
                                              0
                                          ? _audioDuration.inMilliseconds
                                                .toDouble()
                                          : 1.0,
                                      onChanged: (val) {
                                        if (_audioDuration.inMilliseconds > 0 &&
                                            _audioPreviewPlayer != null) {
                                          _audioPreviewPlayer!.seek(
                                            Duration(milliseconds: val.round()),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatAudioDuration(_audioPosition),
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          _formatAudioDuration(_audioDuration),
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_selectedFile != null && _isVideo) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                color: Colors.black,
                                constraints: const BoxConstraints(
                                  maxHeight: 360,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (_videoPreviewController != null &&
                                        _videoPreviewController!
                                            .value
                                            .isInitialized)
                                      AspectRatio(
                                        aspectRatio: _videoPreviewController!
                                            .value
                                            .aspectRatio,
                                        child: VideoPlayer(
                                          _videoPreviewController!,
                                        ),
                                      )
                                    else
                                      const SizedBox(
                                        height: 200,
                                        child: Center(
                                          child: Icon(
                                            Icons.videocam,
                                            color: Colors.white54,
                                            size: 48,
                                          ),
                                        ),
                                      ),
                                    if (_videoPreviewController != null &&
                                        _videoPreviewController!
                                            .value
                                            .isInitialized)
                                      GestureDetector(
                                        onTap: _togglePreviewTrim,
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _videoPreviewController!
                                                    .value
                                                    .isPlaying
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: GestureDetector(
                                        onTap: _clearSelectedMedia,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 8,
                                      left: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.72,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Video${_videoDuration != null ? ' • ${_formatDuration(_videoDuration!)}' : ''}${_fileSizeBytes != null ? ' • ${_formatBytes(_fileSizeBytes!)}' : ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_videoDuration != null &&
                                _videoDuration!.inMilliseconds > 0)
                              VideoTrimmerPanel(
                                durationSeconds:
                                    _videoDuration!.inMilliseconds / 1000.0,
                                maxClipSeconds: _maxVideoSeconds.toDouble(),
                                trimStart: _trimStart,
                                trimEnd: _trimEnd,
                                currentPositionSeconds: _previewPositionSec,
                                isPlaying:
                                    _videoPreviewController?.value.isPlaying ??
                                    false,
                                onSeekTo: (sec) {
                                  _videoPreviewController?.seekTo(
                                    Duration(
                                      milliseconds: (sec * 1000).round(),
                                    ),
                                  );
                                  setState(() => _previewPositionSec = sec);
                                },
                                onTrimChanged: (start, end) {
                                  setState(() {
                                    _trimStart = start;
                                    _trimEnd = end;
                                  });
                                },
                                onTogglePreview: _togglePreviewTrim,
                              ),
                          ],
                          const SizedBox(height: 10),
                          // Action icons
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => _pickMedia(videoMode: false),
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  color: Colors.grey,
                                ),
                                tooltip: 'Gambar',
                              ),
                              IconButton(
                                onPressed: _showVideoSourcePicker,
                                icon: const Icon(
                                  Icons.videocam_outlined,
                                  color: Colors.grey,
                                ),
                                tooltip: 'Video (maks 1,5 menit & 100 MB)',
                              ),
                              IconButton(
                                onPressed: _pickGif,
                                icon: const Icon(
                                  Icons.gif_box_outlined,
                                  color: Colors.grey,
                                ),
                                tooltip: 'GIF',
                              ),
                              IconButton(
                                onPressed: _pickAudio,
                                icon: const Icon(
                                  Icons.music_note_outlined,
                                  color: Colors.grey,
                                ),
                                tooltip: 'Musik',
                              ),
                              IconButton(
                                onPressed: _showCreatePollDialog,
                                icon: const Icon(
                                  Icons.poll_outlined,
                                  color: Colors.grey,
                                ),
                                tooltip: 'Polling',
                              ),
                            ],
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isUploading && _isVideo)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.symmetric(horizontal: 32),
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: primaryColor),
                        SizedBox(height: 14),
                        Text(
                          'Mengunggah video ke Our Media...',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Mohon tunggu sebentar...',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Bottom post button
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isVideo
                        ? 'Maks 1,5 menit • 100 MB'
                        : 'Siapa saja dapat membalas',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  ElevatedButton(
                    onPressed: (_canPost && !_isUploading && !_isCheckingMedia)
                        ? _uploadPost
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: primaryColor.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Posting',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
