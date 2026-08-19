import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TextStatusScreen extends StatefulWidget {
  const TextStatusScreen({super.key});

  @override
  State<TextStatusScreen> createState() => _TextStatusScreenState();
}

class _TextStatusScreenState extends State<TextStatusScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<Color> _bgColors = [
    const Color(0xFF673AB7),
    const Color(0xFFE91E63),
    const Color(0xFFFF5722),
    const Color(0xFF4CAF50),
    const Color(0xFF009688),
    const Color(0xFF00BCD4),
    const Color(0xFF3F51B5),
    const Color(0xFF607D8B),
    const Color(0xFF795548),
  ];
  int _colorIndex = 0;
  bool _isUploading = false;

  void _changeColor() {
    setState(() {
      _colorIndex = (_colorIndex + 1) % _bgColors.length;
    });
  }

  void _uploadStatus() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isUploading = true;
    });

    final bgColorHex = '#${_bgColors[_colorIndex].value.toRadixString(16).substring(2).toUpperCase()}';
    
    final result = await ApiService.uploadTextStory(text, bgColorHex);
    
    setState(() {
      _isUploading = false;
    });

    if (result['success'] == true) {
      if (mounted) Navigator.pop(context, true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Gagal mengunggah status')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColors[_colorIndex],
      body: SafeArea(
        child: Stack(
          children: [
            // Text Input
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: TextField(
                  controller: _textController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  maxLines: null,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Ketik status...',
                    hintStyle: TextStyle(
                      color: Colors.white54,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {}); // Untuk memunculkan tombol kirim jika ada teks
                  },
                ),
              ),
            ),
            
            // Top Controls
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.color_lens, color: Colors.white, size: 30),
                onPressed: _changeColor,
              ),
            ),
            
            // Send Button
            if (_textController.text.trim().isNotEmpty)
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFF0F3460),
                  onPressed: _isUploading ? null : _uploadStatus,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
