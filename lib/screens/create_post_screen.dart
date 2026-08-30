import 'package:flutter/material.dart';
import 'dart:io';
import 'custom_gallery_picker.dart';
import '../services/api_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _captionController = TextEditingController();
  File? _selectedImage;
  bool _isUploading = false;
  bool _canPost = false;

  @override
  void initState() {
    super.initState();
    _captionController.addListener(() {
      setState(() {
        _canPost = _captionController.text.trim().isNotEmpty || _selectedImage != null;
      });
    });
  }

  Future<void> _pickImage() async {
    final pickedFile = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const CustomGalleryPicker(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutQuart;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
    if (pickedFile != null && pickedFile is File) {
      setState(() {
        _selectedImage = pickedFile;
        _canPost = true;
      });
    }
  }

  Future<void> _uploadPost() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty && _selectedImage == null) return;

    setState(() {
      _isUploading = true;
    });

    final res = await ApiService.uploadPost(caption, _selectedImage?.path);

    if (mounted) {
      setState(() {
        _isUploading = false;
      });
      if (res['success'] == true) {
        Navigator.pop(context, true); // Return true to refresh list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Gagal mengunggah')),
        );
      }
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.poll_outlined),
                title: const Text('Polling (Segera Hadir)'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Lokasi (Segera Hadir)'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.format_quote),
                title: const Text('Kutipan (Segera Hadir)'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Utas Baru', style: TextStyle(color: Colors.black)),
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
                          const Text('Anda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          TextField(
                            controller: _captionController,
                            maxLines: null,
                            decoration: const InputDecoration(
                              hintText: 'Mulai utas baru...',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_selectedImage != null)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(_selectedImage!, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedImage = null;
                                        _canPost = _captionController.text.trim().isNotEmpty;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          const SizedBox(height: 10),
                          // Action icons
                          Row(
                            children: [
                              IconButton(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.photo_library_outlined, color: Colors.grey),
                                tooltip: 'Gambar',
                              ),
                              IconButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video belum didukung')));
                                },
                                icon: const Icon(Icons.videocam_outlined, color: Colors.grey),
                                tooltip: 'Video',
                              ),
                              IconButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GIF belum didukung')));
                                },
                                icon: const Icon(Icons.gif_box_outlined, color: Colors.grey),
                                tooltip: 'GIF',
                              ),
                              IconButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Musik belum didukung')));
                                },
                                icon: const Icon(Icons.music_note_outlined, color: Colors.grey),
                                tooltip: 'Music',
                              ),
                              IconButton(
                                onPressed: _showMoreMenu,
                                icon: const Icon(Icons.more_horiz, color: Colors.grey),
                                tooltip: 'Lainnya',
                              ),
                            ],
                          ),
                          const SizedBox(height: 80), // spacer for bottom row
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          // Bottom post button
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!))
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Siapa saja dapat membalas', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ElevatedButton(
                    onPressed: (_canPost && !_isUploading) ? _uploadPost : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: primaryColor.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)
                      )
                    ),
                    child: _isUploading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Posting', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
