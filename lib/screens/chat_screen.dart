import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../widgets/audio_bubble.dart';
import '../widgets/video_bubble.dart';
import '../services/call_manager.dart';
import 'custom_gallery_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'dart:io';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String otherUserName;
  final String otherUserPhone;
  final String? profilePic;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.otherUserName,
    required this.otherUserPhone,
    this.profilePic,
    this.isGroup = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> _messages = [];
  List<dynamic> _groupMembers = [];
  Map<String, String> _contactMap = {};
  bool _isLoading = true;
  String? _error;
  String? _myUserId;
  IO.Socket? _socket;

  // Media Pickers
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  
  bool _isComposing = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _fetchMessages();
    _initSocket();

    _messageController.addListener(() {
      final isNotEmpty = _messageController.text.trim().isNotEmpty;
      if (_isComposing != isNotEmpty) {
        setState(() {
          _isComposing = isNotEmpty;
        });
      }
    });
  }

  void _initSocket() {
    final uri = Uri.parse(ApiService.baseUrl);
    final socketUrl = '${uri.scheme}://${uri.host}:4000';
    
    _socket = IO.io(socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });
    
    _socket!.connect();
    
    _socket!.onConnect((_) {
      _socket!.emit('join', widget.isGroup ? 'group_${widget.roomId}' : widget.roomId);
    });

    _socket!.on('message', (data) {
      if (mounted && data != null) {
        setState(() {
          final exists = _messages.any((m) => m['id'].toString() == data['id'].toString());
          if (!exists) {
            _messages.removeWhere((m) => m['status'] == 'pending' && m['message'] == data['message']);
            _messages.insert(0, data);
          }
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUserId = prefs.getString('user_id');
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final contacts = await DatabaseHelper().getContacts();
      final map = <String, String>{};
      for (var c in contacts) {
        String phone = c['phone_number'].toString().replaceAll(RegExp(r'[^0-9]'), '').trim();
        if (phone.startsWith('62')) {
          phone = '0${phone.substring(2)}';
        }
        map[phone] = c['saved_name'].toString();
      }
      _contactMap = map;
    } catch (e) {
      debugPrint("Gagal load kontak: $e");
    }

    final result = widget.isGroup ? await ApiService.getGroupMessages(widget.roomId) : await ApiService.getChatMessages(widget.roomId);
    if (result['success']) {
      if (mounted) {
        setState(() {
          final List<dynamic> msgs = result['data']['messages'] ?? [];
          _messages = msgs.reversed.toList();
          if (widget.isGroup && result['data']['members'] != null) {
            _groupMembers = result['data']['members'];
          }
          _isLoading = false;
          _error = null;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _error = result['message'];
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final tempMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'sender_id': int.tryParse(_myUserId ?? '0'),
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending', // Added to allow socket listener to remove it
    };
    
    setState(() {
      _messages.insert(0, tempMsg);
      _messageController.clear();
    });
    _scrollToBottom();

    final result = widget.isGroup ? await ApiService.sendGroupMessage(widget.roomId, text) : await ApiService.sendMessage(widget.roomId, text);
    if (!result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim pesan: ${result['message']}')),
        );
      }
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempMsg['id']);
      });
    } else {
      _fetchMessages();
    }
  }

  Future<void> _uploadMedia(String path, String mediaType) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mengirim media...')),
    );

    final result = widget.isGroup ? await ApiService.uploadGroupMedia(widget.roomId, path, mediaType) : await ApiService.uploadMedia(widget.roomId, path, mediaType);
    if (!result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal kirim media: ${result['message']}')),
        );
      }
    } else {
      _fetchMessages();
    }
  }

  void _showAttachmentModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.image, color: Colors.blue),
                title: const Text('Galeri (Gambar/Video)'),
                onTap: () async {
                  Navigator.pop(context);
                  final List<AssetEntity>? assets = await AssetPicker.pickAssets(
                    context,
                    pickerConfig: const AssetPickerConfig(
                      requestType: RequestType.common,
                      maxAssets: 1, // Change if you want multiple upload
                    ),
                  );
                  if (assets != null && assets.isNotEmpty) {
                    final File? file = await assets.first.file;
                    if (file != null) {
                      final type = assets.first.type == AssetType.video ? 'video' : 'image';
                      _uploadMedia(file.path, type);
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.pink),
                title: const Text('Kamera (Gambar)'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomGalleryPicker(
                        showVideoTab: true,
                        showTextTab: false,
                        initialTab: 'kamera',
                      ),
                    ),
                  );
                  
                  if (result != null && result is File) {
                    final type = result.path.toLowerCase().endsWith('.mp4') ? 'video' : 'image';
                    _uploadMedia(result.path, type);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file, color: Colors.orange),
                title: const Text('Dokumen / File'),
                onTap: () async {
                  Navigator.pop(context);
                  FilePickerResult? result = await FilePicker.platform.pickFiles();
                  if (result != null && result.files.single.path != null) {
                    _uploadMedia(result.files.single.path!, 'file');
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        _uploadMedia(path, 'audio');
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin mikrofon diperlukan')),
          );
        }
      }
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.parse(timestamp).toLocal();
    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  bool _isSameDay(String? date1, String? date2) {
    if (date1 == null || date2 == null) return false;
    final d1 = DateTime.parse(date1).toLocal();
    final d2 = DateTime.parse(date2).toLocal();
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  String _formatDateDivider(String? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.parse(timestamp).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);
    
    if (msgDate == today) {
      return 'Hari ini';
    } else if (msgDate == yesterday) {
      return 'Kemarin';
    } else {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }

  Widget _buildMediaContent(dynamic msg, bool isMe) {
    final mediaType = msg['media_type'];
    final mediaUrl = msg['media_url'];

    if (mediaType == null || mediaUrl == null) {
      return Text(
        msg['message'] ?? '',
        style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15),
      );
    }

    if (mediaType == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: ApiService.getServerUrl(mediaUrl),
          width: 200,
          fit: BoxFit.cover,
          placeholder: (context, url) => const SizedBox(
            width: 200, height: 200, child: Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => const Icon(Icons.error),
        ),
      );
    } else if (mediaType == 'video') {
      return VideoBubble(videoUrl: mediaUrl);
    } else if (mediaType == 'audio') {
      return AudioBubble(audioUrl: mediaUrl, isMe: isMe);
    } else if (mediaType == 'file') {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue.shade800 : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              "File Terlampir",
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            )
          ],
        ),
      );
    }

    return Text(msg['message'] ?? '');
  }

  Future<void> _startCall(bool isVideo) async {
    if (widget.isGroup) {
      // Group call: pass groupId so server rings all members
      CallManager.instance.startCall(
        '',
        widget.otherUserName,
        isVideo,
        groupId: widget.roomId.toString(),
      );
    } else {
      CallManager.instance.startCall(widget.otherUserPhone, widget.otherUserName, isVideo);
    }
  }

  String _normalizePhone(String? p) {
    if (p == null) return '';
    String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (num.startsWith('62')) {
      return '0${num.substring(2)}';
    }
    return num;
  }

  String _getGroupSubtitle() {
    if (!widget.isGroup || _groupMembers.isEmpty) return '';
    List<String> names = [];
    for (var m in _groupMembers) {
      if (m['id'].toString() == _myUserId) {
        names.add('Anda');
      } else {
        String phone = _normalizePhone(m['phone']?.toString());
        names.add(_contactMap[phone] ?? m['name'] ?? phone);
      }
    }
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    final subtitle = _getGroupSubtitle();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white24,
              backgroundImage: widget.profilePic != null && widget.profilePic!.isNotEmpty
                  ? CachedNetworkImageProvider(ApiService.getServerUrl(widget.profilePic!))
                  : null,
              child: widget.profilePic == null || widget.profilePic!.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherUserName, style: const TextStyle(fontSize: 18)),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(true),
          ),
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _startCall(false),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _messages.isEmpty
                        ? const Center(child: Text('Belum ada pesan. Ketik pesan pertama Anda!'))
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg['sender_id'].toString() == _myUserId;
                              
                              bool showDateDivider = false;
                              String dateText = "";
                              if (index == _messages.length - 1) {
                                showDateDivider = true;
                                dateText = _formatDateDivider(msg['created_at']);
                              } else {
                                final prevMsg = _messages[index + 1];
                                if (!_isSameDay(msg['created_at'], prevMsg['created_at'])) {
                                  showDateDivider = true;
                                  dateText = _formatDateDivider(msg['created_at']);
                                }
                              }

                              final messageBubble = Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isMe ? primaryColor : Colors.grey.shade200,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                                      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      if (widget.isGroup && !isMe) ...[
                                        Text(
                                          _contactMap[_normalizePhone(msg['phone']?.toString())] ?? msg['name'] ?? 'User',
                                          style: TextStyle(
                                            color: Colors.orange.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                      _buildMediaContent(msg, isMe),
                                      if (msg['caption'] != null && msg['caption'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          msg['caption'],
                                          style: TextStyle(
                                            color: isMe ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _formatTime(msg['created_at']),
                                            style: TextStyle(
                                              color: isMe ? Colors.white70 : Colors.black54,
                                              fontSize: 10,
                                            ),
                                          ),
                                          if (isMe) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              msg['status'] == 'pending' ? Icons.access_time : Icons.done,
                                              size: 12,
                                              color: Colors.white70,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              if (showDateDivider) {
                                return Column(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.symmetric(vertical: 16),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        dateText,
                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    ),
                                    messageBubble,
                                  ],
                                );
                              }
                              return messageBubble;
                            },
                          ),
          ),
          // Input Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.grey),
                    onPressed: _showAttachmentModal,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: _isRecording ? 'Merekam Voice Note...' : 'Ketik pesan...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: _isRecording ? Colors.red.shade50 : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      enabled: !_isRecording,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isComposing)
                    CircleAvatar(
                      backgroundColor: primaryColor,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        onPressed: _sendMessage,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: CircleAvatar(
                        backgroundColor: _isRecording ? Colors.red : primaryColor,
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 20,
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
