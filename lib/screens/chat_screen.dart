import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';
import '../services/encryption_service.dart';
import '../services/database_helper.dart';
import '../widgets/audio_bubble.dart';
import '../widgets/video_bubble.dart';
import '../widgets/poll_bubble.dart';
import '../services/call_manager.dart';
import 'custom_gallery_picker.dart';
import 'contact_info_screen.dart';
import 'create_poll_screen.dart';
import 'poll_votes_screen.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../widgets/ios_message_popup.dart';

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
  late String _activeRoomId;
  bool _isRoomCreatedOnServer = false;

  // Pagination & Reply Jump
  static const int _pageSize = 15;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};

  // Audio & Timer
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  
  bool _isComposing = false;
  bool _isRecording = false;
  Map<String, dynamic>? _replyingToMessage;

  // Multi-select mode
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

  // Group permission state
  bool _isCurrentUserGroupAdmin = false;
  String _sendMessagesPermission = 'all';
  bool get _canSendGroupMessage =>
      !widget.isGroup ||
      _sendMessagesPermission != 'admins_only' ||
      _isCurrentUserGroupAdmin;

  @override
  void initState() {
    super.initState();
    _activeRoomId = widget.roomId;
    _scrollController.addListener(_onScroll);
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
    _socket = IO.io(ApiService.chatSocketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });
    
    _socket!.connect();
    
    _socket!.onConnect((_) {
      _socket!.emit('join', widget.isGroup ? 'group_$_activeRoomId' : _activeRoomId);
      if (_myUserId != null) {
        _socket!.emit('enter_room', {
          'roomId': _activeRoomId,
          'userId': _myUserId,
        });
      }
    });

    _socket!.on('message', (data) async {
      if (mounted && data != null) {
        // Abaikan payload selain pesan chat (misal broadcast vote polling atau tanpa ID)
        if (data['id'] == null || data['pollId'] != null) {
          return;
        }

        if (data['ciphertext'] != null && data['sender_id'].toString() != _myUserId) {
          try {
            final decrypted = EncryptionService.decryptMessage(data['ciphertext']);
            data['message'] = decrypted;
          } catch (e) {
            print('Socket decrypt error: $e');
          }
        }
        setState(() {
          final exists = _messages.any((m) => m['id'].toString() == data['id'].toString());
          if (!exists) {
            _messages.removeWhere((m) => m['status'] == 'pending' && m['message'] == data['message']);
            _messages.insert(0, data);
          }
        });
        _scrollToBottom();

        // Jika pesan dikirim oleh lawan bicara, kirim status delivered dan enter_room
        if (data['sender_id'].toString() != _myUserId) {
          final dynamic rawMsgId = data['id'];
          final int? msgId = rawMsgId is int ? rawMsgId : int.tryParse(rawMsgId?.toString() ?? '');
          final ids = msgId != null ? [msgId] : <int>[];

          if (_socket != null && _socket!.connected && _myUserId != null) {
            _socket!.emit('message:delivered', {
              'roomId': widget.roomId,
              'userId': _myUserId,
              'messageIds': ids,
            });
            // Karena user sedang membuka chat screen, panggil enter_room agar server mengupdate read
            _socket!.emit('enter_room', {
              'roomId': widget.roomId,
              'userId': _myUserId,
            });
          }
          ApiService.markMessagesAsDelivered(widget.roomId, messageIds: ids);
        }
      }
    });

    _socket!.on('messages:delivered', (data) {
      if (mounted && data != null) {
        final List<dynamic>? rawIds = data['messageIds'];
        final List<String>? targetIds = rawIds?.map((e) => e.toString()).toList();
        setState(() {
          for (var msg in _messages) {
            if (targetIds == null || targetIds.isEmpty || targetIds.contains(msg['id'].toString())) {
              msg['is_delivered'] = 1;
            }
          }
        });
      }
    });

    // Listener saat lawan bicara membaca pesan (C2 -> C2 BIRU)
    _socket!.on('messages:read', (data) {
      if (mounted && data != null) {
        final readerId = data['readerId']?.toString();
        if (readerId != _myUserId) {
          setState(() {
            for (var msg in _messages) {
              if (msg['sender_id'].toString() == _myUserId) {
                msg['is_read'] = 1;
                msg['read'] = true;
                msg['is_delivered'] = 1;
              }
            }
          });
        }
      }
    });

    // Listener realtime pembaruan voting / polling grup
    _socket!.on('group:poll_voted', (data) {
      if (mounted && data != null) {
        final pollData = data['poll'];
        final pollId = (data['pollId'] ?? pollData?['id'])?.toString();
        if (pollId != null && pollData != null) {
          setState(() {
            for (var msg in _messages) {
              if (msg['media_type'] == 'poll' && msg['poll'] != null) {
                if (msg['poll']['id']?.toString() == pollId) {
                  final dynamic rawMyVotes = pollData['my_votes'];
                  List<dynamic> myVotesToUse;
                  if (rawMyVotes is List) {
                    myVotesToUse = rawMyVotes;
                  } else {
                    myVotesToUse = List<dynamic>.from(msg['poll']['my_votes'] ?? []);
                  }

                  final updatedOptions = List<dynamic>.from(pollData['options'] ?? []);
                  for (var opt in updatedOptions) {
                    final optId = opt['id'];
                    opt['is_voted_by_me'] = myVotesToUse.contains(optId);
                  }

                  msg['poll']['options'] = updatedOptions;
                  msg['poll']['total_voters'] = pollData['total_voters'] ?? msg['poll']['total_voters'];
                  msg['poll']['my_votes'] = myVotesToUse;
                  break;
                }
              }
            }
          });
        }
      }
    });

    // Listener realtime penghapusan pesan (Hapus untuk saya / Hard delete)
    _socket!.on('messages:deleted', (data) {
      if (mounted && data != null) {
        final deletedBy = data['deletedBy']?.toString();
        final rawIds = (data['messageIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
        final hardDeleted = (data['hardDeletedIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();

        if (deletedBy == _myUserId || hardDeleted.isNotEmpty) {
          setState(() {
            _messages.removeWhere((m) {
              final mId = m['id']?.toString();
              if (mId == null) return false;
              if (deletedBy == _myUserId && rawIds.contains(mId)) return true;
              if (hardDeleted.contains(mId)) return true;
              return false;
            });
          });
        }
      }
    });

    // Listener realtime penarikan pesan (Tarik Pesan / Recall)
    _socket!.on('message:recalled', (data) {
      if (mounted && data != null) {
        final rawMsgId = data['messageId'] ?? data['id'];
        final msgIdStr = rawMsgId?.toString();
        if (msgIdStr != null) {
          setState(() {
            for (var msg in _messages) {
              if (msg['id']?.toString() == msgIdStr) {
                msg['is_recall'] = 1;
                msg['message'] = '';
                msg['media_url'] = null;
                msg['caption'] = null;
                break;
              }
            }
          });
        }
      }
    });
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUserId = prefs.getString('user_id');
    });
    
    // If socket is already connected when userId is loaded, emit enter_room
    if (_socket != null && _socket!.connected && _myUserId != null) {
      _socket!.emit('enter_room', {
        'roomId': widget.roomId,
        'userId': _myUserId,
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (_socket != null && _myUserId != null) {
      _socket!.emit('leave_room', {
        'roomId': widget.roomId,
        'userId': _myUserId,
      });
    }
    _socket?.disconnect();
    _socket?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Pada ListView dengan reverse: true, maxScrollExtent berada di bagian paling atas (pesan lama)
    if (maxScroll - currentScroll <= 250) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreMessages();
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;
    if (!_isRoomCreatedOnServer && !widget.isGroup) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final currentOffset = _messages.length;
      final result = widget.isGroup
          ? await ApiService.getGroupMessages(_activeRoomId, limit: _pageSize, offset: currentOffset)
          : await ApiService.getChatMessages(_activeRoomId, limit: _pageSize, offset: currentOffset);

      if (result['success'] && mounted) {
        final List<dynamic> msgs = result['data']['messages'] ?? [];
        if (msgs.isEmpty) {
          setState(() {
            _hasMore = false;
            _isLoadingMore = false;
          });
          return;
        }

        // Decrypt ciphertext
        for (var i = 0; i < msgs.length; i++) {
          if (msgs[i]['ciphertext'] != null && msgs[i]['type'] != null) {
            try {
              if (msgs[i]['sender_id'].toString() != _myUserId) {
                final decrypted = EncryptionService.decryptMessage(msgs[i]['ciphertext']);
                msgs[i]['message'] = decrypted;
              } else {
                msgs[i]['message'] = msgs[i]['message'] ?? 'Pesan terenkripsi';
              }
            } catch (e) {
              print('Decrypt error: $e');
            }
          }
        }

        // Backend returns oldest-to-newest of that page. Reversing it gives newest-to-oldest,
        // which matches _messages order (0 = newest, last = oldest).
        final olderMsgsReversed = msgs.reversed.toList();
        final existingIds = _messages.map((m) => m['id'].toString()).toSet();
        final List<dynamic> uniqueOlder = [];
        for (var m in olderMsgsReversed) {
          final idStr = m['id'].toString();
          if (!existingIds.contains(idStr)) {
            uniqueOlder.add(m);
            existingIds.add(idStr);
          }
        }

        setState(() {
          _messages.addAll(uniqueOlder);
          _hasMore = msgs.length >= _pageSize && uniqueOlder.isNotEmpty;
          _isLoadingMore = false;
        });

        _checkAndMarkUndeliveredMessages(msgs);
      } else {
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
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

    final result = widget.isGroup 
        ? await ApiService.getGroupMessages(_activeRoomId, limit: _pageSize, offset: 0) 
        : await ApiService.getChatMessages(_activeRoomId, limit: _pageSize, offset: 0);
    if (result['success']) {
      _isRoomCreatedOnServer = true;
      final List<dynamic> msgs = result['data']['messages'] ?? [];
          

                    // Decrypt messages if they have ciphertext

                    for (var i = 0; i < msgs.length; i++) {

                      if (msgs[i]['ciphertext'] != null && msgs[i]['type'] != null) {

                        try {

                           // If we didn't send it, decrypt it using the sender's phone number as ID

                           // Wait, what if we sent it? If we sent it, we can't easily decrypt it unless we encrypt it for ourselves too (Signal handles this via SessionCipher on our own device, but it requires sync).

                           // We actually only encrypt ONE way. This is a prototype limitation!

                           if (msgs[i]['sender_id'].toString() != _myUserId) {

                             final decrypted = EncryptionService.decryptMessage(msgs[i]['ciphertext']);

                             msgs[i]['message'] = decrypted;

                           } else {

                             // Cannot decrypt our own ciphertext without sender keys or sending a copy to ourselves

                             msgs[i]['message'] = msgs[i]['message'] ?? 'Pesan terenkripsi';

                           }

                        } catch (e) {

                           print('Decrypt error: \$e');

                        }

                      }

                    }

        if (mounted) {
          setState(() {
            _messages = msgs.reversed.toList();
            _hasMore = msgs.length >= _pageSize;
            if (widget.isGroup && result['data']['members'] != null) {
              _groupMembers = result['data']['members'];
            }
            _isLoading = false;
            _error = null;
          });

          if (widget.isGroup) {
            final cleanId = _activeRoomId.replaceFirst('group_', '');
            ApiService.getGroupDetails(cleanId).then((groupDetailRes) {
              if (groupDetailRes['success'] == true && groupDetailRes['data'] != null && mounted) {
                final g = groupDetailRes['data'];
                setState(() {
                  _sendMessagesPermission = g['send_messages_permission'] ?? 'all';
                  final currentUser = g['current_user'];
                  _isCurrentUserGroupAdmin = currentUser?['is_admin'] == true;
                });
              }
            }).catchError((_) {});
          }

          // Deteksi pesan dari lawan bicara yang belum berstatus delivered
          _checkAndMarkUndeliveredMessages(msgs);
        }
    } else {
      if (mounted) {
        setState(() {
          if (!widget.isGroup) {
            // Room lokal baru belum dibuat di server, ini bukan error
            _messages = [];
            _error = null;
            _isRoomCreatedOnServer = false;
            _hasMore = false;
          } else {
            _error = result['message'];
          }
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
    if (!_canSendGroupMessage) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final int? replyToId = _replyingToMessage?['id'] is int 
        ? _replyingToMessage!['id'] 
        : int.tryParse(_replyingToMessage?['id']?.toString() ?? '');
    final String? replyToMediaType = _replyingToMessage?['media_type']?.toString();
    final String? replyToSenderName = _replyingToMessage != null 
        ? (_replyingToMessage!['sender_id'].toString() == _myUserId 
            ? 'Anda' 
            : (_contactMap[_normalizePhone(_replyingToMessage!['phone']?.toString())] ?? _replyingToMessage!['name'] ?? 'User'))
        : null;
    final String? replyToMessage = _replyingToMessage != null
        ? (_replyingToMessage!['message'] != null && _replyingToMessage!['message'].toString().isNotEmpty
            ? _replyingToMessage!['message'].toString()
            : _getMediaTypeLabel(replyToMediaType))
        : null;

    final tempMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'sender_id': int.tryParse(_myUserId ?? '0'),
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending', 
      'reply_to_id': replyToId,
      'reply_to_sender_name': replyToSenderName,
      'reply_to_message': replyToMessage,
      'reply_to_media_type': replyToMediaType,
      'reply_message': replyToMessage,
      'reply_sender_name': replyToSenderName,
      'reply_media_type': replyToMediaType,
    };

    setState(() {
      _messages.insert(0, tempMsg);
      _messageController.clear();
      _replyingToMessage = null;
    });
    _scrollToBottom();

    String? ciphertext;
    String? cipherType;

    if (!widget.isGroup) {
      try {
        ciphertext = EncryptionService.encryptMessage(text);
        cipherType = 'normal';
      } catch (e) {
        print('Encryption error: $e');
      }
    }

    Map<String, dynamic> result;
    if (widget.isGroup) {
      result = await ApiService.sendGroupMessage(
        _activeRoomId, 
        text, 
        replyToId: replyToId,
        replyToSenderName: replyToSenderName,
        replyToMessage: replyToMessage,
        replyToMediaType: replyToMediaType,
        ciphertext: ciphertext,
        type: cipherType,
      );
    } else if (!_isRoomCreatedOnServer) {
      // Buat room di server secara atomik dengan ID lokal unik + kirim pesan pertama!
      result = await ApiService.createChatRoomAndSendMessage(
        phone: widget.otherUserPhone,
        roomId: _activeRoomId,
        message: text,
        replyToId: replyToId,
        replyToSenderName: replyToSenderName,
        replyToMessage: replyToMessage,
        replyToMediaType: replyToMediaType,
      );
      if (result['success']) {
        _isRoomCreatedOnServer = true;
        if (result['chatRoomId'] != null) {
          _activeRoomId = result['chatRoomId'].toString();
          // Simpan/sinkronkan room ID ke database SQLite lokal
          await DatabaseHelper().saveContact(
            widget.otherUserPhone,
            widget.otherUserName,
            isRegistered: true,
            localRoomId: _activeRoomId,
          );
          // Bergabung ke room socket realtime
          _socket?.emit('join', _activeRoomId);
          if (_myUserId != null) {
            _socket?.emit('enter_room', {
              'roomId': _activeRoomId,
              'userId': _myUserId,
            });
          }
        }
      }
    } else {
      result = await ApiService.sendMessage(
        _activeRoomId, 
        text, 
        replyToId: replyToId, 
        replyToSenderName: replyToSenderName,
        replyToMessage: replyToMessage,
        replyToMediaType: replyToMediaType,
        ciphertext: ciphertext, 
        type: cipherType,
      );
      // Fallback jika terjadi error FK constraint:
      if (!result['success'] && (result['message'] ?? '').toString().toLowerCase().contains('foreign key')) {
        result = await ApiService.createChatRoomAndSendMessage(
          phone: widget.otherUserPhone,
          roomId: _activeRoomId,
          message: text,
          replyToId: replyToId,
          replyToSenderName: replyToSenderName,
          replyToMessage: replyToMessage,
          replyToMediaType: replyToMediaType,
        );
        if (result['success']) {
          _isRoomCreatedOnServer = true;
        }
      }
    }

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

  Future<void> _uploadMedia(String path, String mediaType, {String caption = ''}) async {
    final int? replyToId = _replyingToMessage?['id'] is int 
        ? _replyingToMessage!['id'] 
        : int.tryParse(_replyingToMessage?['id']?.toString() ?? '');
    final String? replyToMediaType = _replyingToMessage?['media_type']?.toString();
    final String? replyToSenderName = _replyingToMessage != null 
        ? (_replyingToMessage!['sender_id'].toString() == _myUserId 
            ? 'Anda' 
            : (_contactMap[_normalizePhone(_replyingToMessage!['phone']?.toString())] ?? _replyingToMessage!['name'] ?? 'User'))
        : null;
    final String? replyToMessage = _replyingToMessage != null
        ? (_replyingToMessage!['message'] != null && _replyingToMessage!['message'].toString().isNotEmpty
            ? _replyingToMessage!['message'].toString()
            : _getMediaTypeLabel(replyToMediaType))
        : null;

    if (_replyingToMessage != null) {
      setState(() {
        _replyingToMessage = null;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mengirim media...'), duration: Duration(seconds: 1)),
    );

    // Pastikan room aktif di server sebelum kirim media
    if (!widget.isGroup && !_isRoomCreatedOnServer) {
      final createRes = await ApiService.createChatRoomAndSendMessage(
        phone: widget.otherUserPhone,
        roomId: _activeRoomId,
        message: 'Mengirim lampiran media',
      );
      if (createRes['success']) {
        _isRoomCreatedOnServer = true;
        if (createRes['chatRoomId'] != null) {
          _activeRoomId = createRes['chatRoomId'].toString();
        }
      }
    }

    final result = widget.isGroup 
        ? await ApiService.uploadGroupMedia(
            _activeRoomId, 
            path, 
            mediaType,
            caption: caption,
            replyToId: replyToId,
            replyToSenderName: replyToSenderName,
            replyToMessage: replyToMessage,
            replyToMediaType: replyToMediaType,
          ) 
        : await ApiService.uploadMedia(
            _activeRoomId, 
            path, 
            mediaType,
            caption: caption,
            replyToId: replyToId,
            replyToSenderName: replyToSenderName,
            replyToMessage: replyToMessage,
            replyToMediaType: replyToMediaType,
          );

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
                      maxAssets: 1,
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
                leading: const Icon(Icons.gif_box_rounded, color: Colors.teal),
                title: const Text('GIF Animasi'),
                onTap: () {
                  Navigator.pop(context);
                  _showGifPicker();
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
              if (widget.isGroup)
                ListTile(
                  leading: const Icon(Icons.poll_rounded, color: Colors.deepPurple, size: 26),
                  title: const Text('Polling / Voting'),
                  subtitle: const Text('Buat pemungutan suara untuk anggota grup'),
                  onTap: () {
                    Navigator.pop(context);
                    _openCreatePollScreen();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _openCreatePollScreen() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePollScreen(groupId: widget.roomId),
      ),
    );
    if (created == true) {
      _fetchMessages();
    }
  }

  Future<void> _voteOnPoll(Map<String, dynamic> msg, int optionId) async {
    final poll = msg['poll'];
    if (poll == null) return;
    final pollId = poll['id'];
    final cleanId = widget.roomId.replaceFirst('group_', '');

    // Optimistic UI update
    final bool isMultiple = poll['multiple_answers'] == true || poll['multiple_answers'] == 1;
    final options = List<dynamic>.from(poll['options'] ?? []);
    final myVotes = List<dynamic>.from(poll['my_votes'] ?? []);

    final bool currentlyVoted = myVotes.contains(optionId);
    if (currentlyVoted) {
      myVotes.remove(optionId);
    } else {
      if (!isMultiple) {
        myVotes.clear();
      }
      myVotes.add(optionId);
    }

    setState(() {
      poll['my_votes'] = myVotes;
      for (var opt in options) {
        final optId = opt['id'];
        final wasVoted = opt['is_voted_by_me'] == true;
        final isNowVoted = myVotes.contains(optId);
        opt['is_voted_by_me'] = isNowVoted;
        if (!wasVoted && isNowVoted) {
          opt['vote_count'] = (opt['vote_count'] ?? 0) + 1;
        } else if (wasVoted && !isNowVoted) {
          opt['vote_count'] = ((opt['vote_count'] ?? 1) - 1).clamp(0, 999999);
        }
      }
    });

    final res = await ApiService.voteGroupPoll(cleanId, pollId, optionId: optionId);
    if (res['success'] == true && res['data'] != null && mounted) {
      setState(() {
        msg['poll'] = res['data'];
      });
    } else if (res['success'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Gagal memproses vote')),
      );
      _fetchMessages();
    }
  }

  void _viewPollVotes(Map<String, dynamic> msg) {
    final poll = msg['poll'];
    if (poll == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PollVotesScreen(
          groupId: widget.roomId,
          pollId: poll['id'],
          initialQuestion: poll['question'],
        ),
      ),
    );
  }

  final List<Map<String, String>> _popularGifs = const [
    {'title': 'Ketawa', 'url': 'https://media.giphy.com/media/26n6Gx9moCgs1qxmg/giphy.gif'},
    {'title': 'Senang', 'url': 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif'},
    {'title': 'Jempol', 'url': 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif'},
    {'title': 'Tepuk Tangan', 'url': 'https://media.giphy.com/media/ely3apij36BJhoZ234/giphy.gif'},
    {'title': 'Kaget', 'url': 'https://media.giphy.com/media/5VKbvrjxpVJCM/giphy.gif'},
    {'title': 'Joget', 'url': 'https://media.giphy.com/media/blSTtZehjAZ8I/giphy.gif'},
    {'title': 'Sedih', 'url': 'https://media.giphy.com/media/7SF5scGB2AFrgsXP63/giphy.gif'},
    {'title': 'Love', 'url': 'https://media.giphy.com/media/MDJ9IbxxvDUQM/giphy.gif'},
    {'title': 'Dadah', 'url': 'https://media.giphy.com/media/dzaUX7CAG0Ihi/giphy.gif'},
    {'title': 'Mikir', 'url': 'https://media.giphy.com/media/d3mlE7uhX8KFgEmY/giphy.gif'},
    {'title': 'Semangat', 'url': 'https://media.giphy.com/media/3o7abKhOpu0NwenH3O/giphy.gif'},
    {'title': 'Keren', 'url': 'https://media.giphy.com/media/l41lI4bYmcsPJX9Go/giphy.gif'},
  ];

  Future<void> _sendGifFromUrl(String url) async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Menyiapkan GIF...'), duration: Duration(seconds: 1)),
    );
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/gif_${DateTime.now().millisecondsSinceEpoch}.gif');
        await file.writeAsBytes(response.bodyBytes);
        await _uploadMedia(file.path, 'gif');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal mengunduh GIF')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error mengirim GIF: $e')),
        );
      }
    }
  }

  Future<void> _pickGifFromDevice() async {
    Navigator.pop(context);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif'],
      );
      if (result != null && result.files.single.path != null) {
        await _uploadMedia(result.files.single.path!, 'gif');
      }
    } catch (e) {
      debugPrint('Error pick GIF: $e');
    }
  }

  void _showGifPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pilih GIF Animasi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: _pickGifFromDevice,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Dari File'),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: _popularGifs.length,
                  itemBuilder: (context, index) {
                    final item = _popularGifs[index];
                    return InkWell(
                      onTap: () => _sendGifFromUrl(item['url']!),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                child: CachedNetworkImage(
                                  imageUrl: item['url']!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  placeholder: (c, u) => const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: (c, u, e) => const Icon(Icons.error, color: Colors.grey),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              alignment: Alignment.center,
                              child: Text(
                                item['title']!,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration++;
        });
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingDuration = 0;
  }

  String _formatRecordingDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleRecording({bool cancelOnly = false}) async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      _stopRecordingTimer();
      setState(() => _isRecording = false);
      if (!cancelOnly && path != null) {
        _uploadMedia(path, 'audio');
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        setState(() => _isRecording = true);
        _startRecordingTimer();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin mikrofon diperlukan')),
          );
        }
      }
    }
  }

  String _getMediaTypeLabel(String? mediaType) {
    switch (mediaType) {
      case 'audio':
        return 'Pesan Suara';
      case 'gif':
        return 'GIF';
      case 'image':
        return 'Foto';
      case 'video':
        return 'Video';
      case 'file':
        return 'Dokumen';
      case 'poll':
        return '📊 Polling';
      default:
        return 'Media';
    }
  }

  IconData _getMediaIconData(String? mediaType) {
    switch (mediaType) {
      case 'audio':
        return Icons.mic;
      case 'gif':
        return Icons.gif_box_rounded;
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'file':
        return Icons.insert_drive_file;
      case 'poll':
        return Icons.poll_rounded;
      default:
        return Icons.message;
    }
  }

  Future<void> _scrollToMessageById(dynamic targetId) async {
    if (targetId == null) return;
    final idStr = targetId.toString().trim();
    if (idStr.isEmpty) return;

    int index = _messages.indexWhere((m) => m['id']?.toString() == idStr);

    // Jika pesan yang dibalas lebih lama dari pesan yang sudah dimuat, fetch batch sebelumnya
    if (index == -1 && _hasMore) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memuat pesan yang dibalas...'),
            duration: Duration(milliseconds: 1000),
          ),
        );
      }

      int attempts = 0;
      while (index == -1 && _hasMore && attempts < 10) {
        attempts++;
        await _loadMoreMessages();
        index = _messages.indexWhere((m) => m['id']?.toString() == idStr);
      }
    }

    if (index == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesan yang dibalas tidak ditemukan'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Sorot pesan dengan efek highlight
    if (mounted) {
      setState(() {
        _highlightedMessageId = idStr;
      });
    }

    // Gulir ke pesan tersebut dan posisikan di tengah layar
    if (_scrollController.hasClients) {
      final key = _messageKeys[idStr];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          alignment: 0.5,
        );
      } else {
        // Jika belum ter-render di viewport, arahkan scroll mendekati posisinya
        final maxScroll = _scrollController.position.maxScrollExtent;
        final approxOffset = (index * 85.0).clamp(0.0, maxScroll);
        await _scrollController.animateTo(
          approxOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        );
        // Beri waktu sejenak agar ListView me-mount widget
        await Future.delayed(const Duration(milliseconds: 120));
        if (!mounted) return;
        final ctx = _messageKeys[idStr]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: 0.5,
          );
        }
      }
    }

    // Hapus efek highlight setelah 1.8 detik
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _highlightedMessageId == idStr) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  void _showIosContextMenu(Map<String, dynamic> msg, bool isMe) {
    final msgIdStr = msg['id'].toString();
    final key = _messageKeys[msgIdStr];
    if (key?.currentContext == null) return;

    final RenderBox? box = key!.currentContext!.findRenderObject() as RenderBox?;
    if (box == null) return;

    final position = box.localToGlobal(Offset.zero);
    final size = box.size;
    final messageRect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

    // Render clone bubble yang mengambang dengan dimensi dan styling yang sama persis
    final floatingBubble = _buildBubbleContent(msg, isMe, isInteractive: false);
    final isRecall = msg['is_recall'] == 1 || msg['is_recall'] == true;
    final canRecall = isMe && !isRecall;

    List<IosMessageAction> row1Actions;
    List<IosMessageAction> row2Actions;

    if (isRecall) {
      row1Actions = [
        IosMessageAction(
          label: 'Hapus',
          icon: Icons.delete_outline_rounded,
          isDestructive: true,
          onTap: () {
            _confirmDeleteMessage(Map<String, dynamic>.from(msg));
          },
        ),
        IosMessageAction(
          label: 'Pilih',
          icon: Icons.checklist_rounded,
          onTap: () {
            setState(() {
              _isSelectionMode = true;
              _selectedMessageIds.clear();
              _selectedMessageIds.add(msgIdStr);
            });
          },
        ),
      ];
      row2Actions = [];
    } else {
      row1Actions = [
        IosMessageAction(
          label: 'Salin',
          icon: Icons.copy_rounded,
          onTap: () {
            final text = msg['message']?.toString() ?? '';
            if (text.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Teks disalin ke clipboard')),
              );
            }
          },
        ),
        IosMessageAction(
          label: 'Teruskan',
          icon: Icons.shortcut_rounded,
          onTap: () {
            _forwardSingleMessage(msg);
          },
        ),
        if (canRecall)
          IosMessageAction(
            label: 'Tarik Pesan',
            icon: Icons.undo_rounded,
            isDestructive: true,
            onTap: () {
              _confirmRecallMessage(Map<String, dynamic>.from(msg));
            },
          )
        else
          IosMessageAction(
            label: 'Tambahkan ke\nPesan Favorit',
            icon: Icons.view_in_ar_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pesan ditambahkan ke Pesan Favorit')),
              );
            },
          ),
        IosMessageAction(
          label: 'Hapus',
          icon: Icons.delete_outline_rounded,
          isDestructive: true,
          onTap: () {
            _confirmDeleteMessage(Map<String, dynamic>.from(msg));
          },
        ),
        IosMessageAction(
          label: 'Pilih',
          icon: Icons.checklist_rounded,
          onTap: () {
            setState(() {
              _isSelectionMode = true;
              _selectedMessageIds.clear();
              _selectedMessageIds.add(msgIdStr);
            });
          },
        ),
      ];

      row2Actions = [
        IosMessageAction(
          label: 'Kutip',
          icon: Icons.format_quote_rounded,
          onTap: () {
            setState(() {
              _replyingToMessage = msg;
            });
          },
        ),
        if (canRecall)
          IosMessageAction(
            label: 'Tambahkan ke\nPesan Favorit',
            icon: Icons.view_in_ar_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pesan ditambahkan ke Pesan Favorit')),
              );
            },
          )
        else
          IosMessageAction(
            label: 'Pengingat',
            icon: Icons.notifications_none_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pengingat telah disetel')),
              );
            },
          ),
        IosMessageAction(
          label: 'Terjemahkan',
          icon: Icons.translate_rounded,
          onTap: () {
            _showTranslationDialog(msg);
          },
        ),
        IosMessageAction(
          label: 'Cari',
          icon: Icons.search_rounded,
          onTap: () {
            _showSearchDialog(msg);
          },
        ),
        IosMessageAction(
          label: 'Baca Teks',
          icon: Icons.volume_up_outlined,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Membaca pesan...')),
            );
          },
        ),
      ];
    }

    Navigator.push(
      context,
      IosMessagePopupRoute(
        messageRect: messageRect,
        messageBubble: floatingBubble,
        isMe: isMe,
        row1Actions: row1Actions,
        row2Actions: row2Actions,
      ),
    );
  }

  void _toggleMessageSelection(String msgIdStr) {
    setState(() {
      if (_selectedMessageIds.contains(msgIdStr)) {
        _selectedMessageIds.remove(msgIdStr);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(msgIdStr);
      }
    });
  }

  void _copySelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    final selectedMsgs = _messages
        .where((m) => _selectedMessageIds.contains(m['id']?.toString()))
        .toList();
    selectedMsgs.sort((a, b) {
      final tA = a['created_at']?.toString() ?? '';
      final tB = b['created_at']?.toString() ?? '';
      return tA.compareTo(tB);
    });

    final texts = selectedMsgs
        .map((m) => m['message']?.toString())
        .where((t) => t != null && t.isNotEmpty)
        .join('\n');

    if (texts.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: texts));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_selectedMessageIds.length} pesan disalin')),
      );
    }

    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _forwardSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    final count = _selectedMessageIds.length;
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Teruskan $count pesan')),
    );
  }

  void _forwardSingleMessage(dynamic msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teruskan pesan')),
    );
  }

  void _showTranslationDialog(dynamic msg) {
    final text = msg['message']?.toString() ?? '';
    if (text.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.translate, color: Color(0xFF0F3460)),
                SizedBox(width: 8),
                Text('Terjemahan Pesan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(fontSize: 15, color: Colors.black87)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchDialog(dynamic msg) {
    final text = msg['message']?.toString() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Mencari "$text" dalam obrolan')),
    );
  }

  void _confirmDeleteSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    final count = _selectedMessageIds.length;
    final selectedMsgs = _messages.where((m) => _selectedMessageIds.contains(m['id']?.toString())).toList();
    final allMine = selectedMsgs.every((m) => m['sender_id']?.toString() == _myUserId && m['is_recall'] != 1);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade600,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hapus $count pesan?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                allMine
                    ? 'Anda dapat menarik pesan terpilih untuk semua orang atau menghapusnya untuk Anda saja.'
                    : 'Pesan terpilih akan dihapus untuk Anda dari obrolan ini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              if (allMine) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.undo_rounded, size: 20),
                    label: Text(
                      'Tarik $count Pesan untuk Semua Orang',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _recallSelectedMessages();
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allMine ? Colors.grey.shade100 : Colors.red.shade600,
                    foregroundColor: allMine ? const Color(0xFF374151) : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: allMine ? const Color(0xFF4B5563) : Colors.white,
                  ),
                  label: Text(
                    'Hapus untuk Saya',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: allMine ? const Color(0xFF374151) : Colors.white,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteSelectedMessages();
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Batal',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recallSelectedMessages() async {
    final ids = _selectedMessageIds.toList();
    if (ids.isEmpty) return;

    final count = ids.length;
    setState(() {
      for (var id in ids) {
        final idx = _messages.indexWhere((m) => m['id']?.toString() == id.toString());
        if (idx != -1) {
          _messages[idx]['is_recall'] = 1;
          _messages[idx]['message'] = '';
          _messages[idx]['media_url'] = null;
          _messages[idx]['caption'] = null;
        }
      }
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });

    for (var id in ids) {
      if (widget.isGroup) {
        await ApiService.recallGroupMessage(_activeRoomId, id);
      } else {
        await ApiService.recallChatMessage(_activeRoomId, id);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count pesan berhasil ditarik untuk semua orang'),
          backgroundColor: const Color(0xFF0F3460),
        ),
      );
    }
  }

  Future<void> _deleteSelectedMessages() async {
    final ids = _selectedMessageIds.toList();
    if (ids.isEmpty) return;

    final count = ids.length;
    final backup = List<dynamic>.from(_messages);

    setState(() {
      _messages.removeWhere((m) => ids.contains(m['id']?.toString()));
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });

    final res = widget.isGroup
        ? await ApiService.deleteGroupMessage(_activeRoomId, ids.first, messageIds: ids)
        : await ApiService.deleteChatMessage(_activeRoomId, ids.first, messageIds: ids);

    if (!res['success'] && mounted) {
      setState(() {
        _messages = backup;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Gagal menghapus pesan')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count pesan telah dihapus untuk Anda'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _confirmRecallMessage(Map<String, dynamic> msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.undo_rounded,
                    color: Colors.orange.shade800,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tarik pesan ini?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pesan akan ditarik untuk semua orang di obrolan ini. Anggota lain akan melihat bahwa pesan ini telah ditarik.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.undo_rounded, size: 20),
                  label: const Text(
                    'Tarik Pesan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _recallMessage(msg);
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Batal',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recallMessage(Map<String, dynamic> msg) async {
    final msgId = msg['id'];
    if (msgId == null) return;

    final int index = _messages.indexWhere((m) => m['id']?.toString() == msgId.toString());
    final backupMsg = index != -1 ? Map<String, dynamic>.from(_messages[index]) : null;

    if (index != -1) {
      setState(() {
        _messages[index]['is_recall'] = 1;
        _messages[index]['message'] = '';
        _messages[index]['media_url'] = null;
        _messages[index]['caption'] = null;
      });
    }

    final res = widget.isGroup
        ? await ApiService.recallGroupMessage(_activeRoomId, msgId)
        : await ApiService.recallChatMessage(_activeRoomId, msgId);

    if (!res['success']) {
      if (index != -1 && backupMsg != null && mounted) {
        setState(() {
          _messages[index] = backupMsg;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Gagal menarik pesan'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesan berhasil ditarik untuk semua orang'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF0F3460),
          ),
        );
      }
    }
  }

  void _confirmDeleteMessage(Map<String, dynamic> msg) {
    final msgId = msg['id'];
    if (msgId == null) return;
    final isMe = msg['sender_id']?.toString() == _myUserId;
    final isRecall = msg['is_recall'] == 1 || msg['is_recall'] == true;
    final canRecall = isMe && !isRecall;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade600,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hapus pesan?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                canRecall
                    ? 'Pilih tindakan untuk pesan ini. Anda dapat menarik pesan dari semua orang atau hanya menghapusnya untuk Anda.'
                    : 'Pesan ini akan dihapus dari riwayat obrolan Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              if (canRecall) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.undo_rounded, size: 20),
                    label: const Text(
                      'Tarik untuk Semua Orang',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _recallMessage(msg);
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canRecall ? Colors.grey.shade100 : Colors.red.shade600,
                    foregroundColor: canRecall ? const Color(0xFF374151) : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: canRecall ? const Color(0xFF4B5563) : Colors.white,
                  ),
                  label: Text(
                    'Hapus untuk Saya',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: canRecall ? const Color(0xFF374151) : Colors.white,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteMessage(msg);
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Batal',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final msgId = msg['id'];
    if (msgId == null) return;

    final int index = _messages.indexWhere((m) => m['id']?.toString() == msgId.toString());
    if (index != -1) {
      setState(() {
        _messages.removeAt(index);
      });
    }

    final res = widget.isGroup
        ? await ApiService.deleteGroupMessage(_activeRoomId, msgId)
        : await ApiService.deleteChatMessage(_activeRoomId, msgId);

    if (!res['success']) {
      if (index != -1 && mounted) {
        setState(() {
          _messages.insert(index, msg);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Gagal menghapus pesan')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesan telah dihapus untuk Anda'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Widget _buildBubbleContent(
    dynamic msg,
    bool isMe, {
    Key? key,
    bool isHighlighted = false,
    bool isInteractive = true,
  }) {
    const primaryColor = Color(0xFF0F3460);
    final screenWidth = MediaQuery.of(context).size.width;
    final isRecall = msg['is_recall'] == 1 || msg['is_recall'] == true;

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
    );

    final bubbleBgColor = isHighlighted
        ? (isMe ? primaryColor.withOpacity(0.85) : Colors.amber.shade100)
        : (isMe ? primaryColor : Colors.grey.shade200);

    return Container(
      key: key,
      constraints: BoxConstraints(
        maxWidth: screenWidth * 0.75,
        minWidth: 72,
      ),
      decoration: isHighlighted
          ? BoxDecoration(
              borderRadius: bubbleRadius,
              border: Border.all(color: Colors.amber.shade700, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            )
          : null,
      child: Material(
        color: bubbleBgColor,
        borderRadius: bubbleRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: bubbleRadius,
          splashColor: isMe
              ? Colors.black.withOpacity(0.24)
              : Colors.black.withOpacity(0.12),
          highlightColor: isMe
              ? Colors.black.withOpacity(0.20)
              : Colors.black.withOpacity(0.10),
          hoverColor: Colors.black.withOpacity(0.05),
          onTap: isInteractive
              ? () {
                  if (_isSelectionMode) {
                    _toggleMessageSelection(msg['id'].toString());
                  }
                }
              : null,
          onLongPress: isInteractive
              ? () {
                  if (_isSelectionMode) {
                    _toggleMessageSelection(msg['id'].toString());
                  } else {
                    _showIosContextMenu(Map<String, dynamic>.from(msg), isMe);
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isRecall) ...[
                    _buildQuotedReply(msg, isMe),
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
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block_rounded,
                            size: 15,
                            color: isMe ? Colors.white70 : Colors.black45,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isMe ? 'Anda telah menarik pesan ini' : 'Pesan ini telah ditarik',
                              style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.black54,
                                fontSize: 13.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(msg['created_at']),
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe && !isRecall) ...[
                        const SizedBox(width: 4),
                        _buildStatusIcon(msg),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuotedReply(dynamic msg, bool isMe) {
    final replyId = msg['reply_to_id'] ?? msg['replyToId'];
    final replySender = msg['reply_to_sender_name'] ?? msg['replyToSenderName'] ?? msg['reply_sender_name'];
    final replyText = msg['reply_to_message'] ?? msg['replyToMessage'] ?? msg['reply_message'];
    final replyMediaType = msg['reply_to_media_type'] ?? msg['replyToMediaType'] ?? msg['reply_media_type'];

    if (replyId == null && replyText == null && replySender == null) {
      return const SizedBox.shrink();
    }

    final accentColor = isMe ? Colors.white70 : const Color(0xFF0F3460);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: replyId != null ? () => _scrollToMessageById(replyId) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isMe ? Colors.black.withOpacity(0.18) : Colors.black.withOpacity(0.06),
          border: Border(left: BorderSide(color: isMe ? Colors.white : accentColor, width: 3.5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              replySender ?? 'Pesan Balasan',
              style: TextStyle(
                color: isMe ? Colors.white : accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyMediaType != null && replyMediaType.toString().isNotEmpty) ...[
                  Icon(
                    _getMediaIconData(replyMediaType.toString()),
                    size: 13,
                    color: isMe ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    (replyText != null && replyText.toString().isNotEmpty) 
                        ? replyText.toString() 
                        : _getMediaTypeLabel(replyMediaType?.toString()),
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.black87,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    const primaryColor = Color(0xFF0F3460);
    final senderName = _replyingToMessage!['sender_id'].toString() == _myUserId 
        ? 'Anda' 
        : (_contactMap[_normalizePhone(_replyingToMessage!['phone']?.toString())] ?? _replyingToMessage!['name'] ?? 'User');
    final mediaType = _replyingToMessage!['media_type']?.toString();
    final text = _replyingToMessage!['message'];
    final displayText = (text != null && text.toString().isNotEmpty) 
        ? text.toString() 
        : _getMediaTypeLabel(mediaType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: const Border(left: BorderSide(color: primaryColor, width: 4)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.reply, size: 14, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'Membalas $senderName',
                      style: const TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (mediaType != null && mediaType.isNotEmpty) ...[
                      Icon(_getMediaIconData(mediaType), size: 14, color: Colors.black54),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        displayText,
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.black54),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
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

    if (mediaType == 'poll' || msg['poll'] != null) {
      return PollBubble(
        message: Map<String, dynamic>.from(msg),
        isMe: isMe,
        onVote: (optionId) => _voteOnPoll(msg, optionId),
        onViewVotes: () => _viewPollVotes(msg),
      );
    }

    if (mediaType == null || mediaUrl == null) {
      return Text(
        msg['message'] ?? '',
        style: TextStyle(
          color: isMe ? Colors.white : Colors.black87,
          fontSize: 15,
          height: 1.25,
        ),
        softWrap: true,
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
    } else if (mediaType == 'gif') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CachedNetworkImage(
              imageUrl: ApiService.getServerUrl(mediaUrl),
              width: 220,
              fit: BoxFit.cover,
              placeholder: (context, url) => const SizedBox(
                width: 200, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (context, url, error) => Container(
                width: 200,
                height: 120,
                color: Colors.grey.shade300,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.grey),
                    SizedBox(height: 4),
                    Text('Gagal memuat GIF', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'GIF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
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
      appBar: _isSelectionMode
          ? AppBar(
              backgroundColor: const Color(0xFF0F3460),
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedMessageIds.clear();
                  });
                },
              ),
              title: Text(
                '${_selectedMessageIds.length} dipilih',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Salin',
                  onPressed: _selectedMessageIds.isEmpty ? null : _copySelectedMessages,
                ),
                IconButton(
                  icon: const Icon(Icons.shortcut_rounded),
                  tooltip: 'Teruskan',
                  onPressed: _selectedMessageIds.isEmpty ? null : _forwardSelectedMessages,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Hapus',
                  onPressed: _selectedMessageIds.isEmpty ? null : _confirmDeleteSelectedMessages,
                ),
              ],
            )
          : AppBar(
              title: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 320),
                      reverseTransitionDuration: const Duration(milliseconds: 280),
                      pageBuilder: (context, animation, secondaryAnimation) => ContactInfoScreen(
                        phone: widget.otherUserPhone,
                        displayName: widget.otherUserName,
                        profilePic: widget.profilePic,
                        roomId: widget.roomId,
                        isGroup: widget.isGroup,
                      ),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        );
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(1.0, 0.0),
                            end: Offset.zero,
                          ).animate(curved),
                          child: FadeTransition(
                            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
                            child: child,
                          ),
                        );
                      },
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
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
                ),
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
                            itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.5),
                                    ),
                                  ),
                                );
                              }

                              final msg = _messages[index];
                              final isMe = msg['sender_id'].toString() == _myUserId;
                              final msgIdStr = msg['id'].toString();
                              final isHighlighted = _highlightedMessageId == msgIdStr;
                              
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

                              final isSelected = _selectedMessageIds.contains(msgIdStr);

                              final bubbleContent = _buildBubbleContent(
                                msg,
                                isMe,
                                key: _messageKeys.putIfAbsent(msgIdStr, () => GlobalKey()),
                                isHighlighted: isHighlighted,
                              );

                              final isMsgRecalled = msg['is_recall'] == 1 || msg['is_recall'] == true;

                              final rawBubble = SwipeToReply(
                                onReply: () {
                                  if (!_isSelectionMode && !isMsgRecalled) {
                                    setState(() {
                                      _replyingToMessage = msg;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: bubbleContent,
                                ),
                              );

                              final messageBubble = _isSelectionMode
                                  ? InkWell(
                                      onTap: () => _toggleMessageSelection(msgIdStr),
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      child: Container(
                                        color: isSelected
                                            ? const Color(0xFF0F3460).withOpacity(0.12)
                                            : Colors.transparent,
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(left: 12.0),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 180),
                                                width: 22,
                                                height: 22,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isSelected ? const Color(0xFF25D366) : Colors.transparent,
                                                  border: Border.all(
                                                    color: isSelected ? const Color(0xFF25D366) : Colors.grey.shade400,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: isSelected
                                                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                                                    : null,
                                              ),
                                            ),
                                            Expanded(child: rawBubble),
                                          ],
                                        ),
                                      ),
                                    )
                                  : rawBubble;

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
          if (!_isSelectionMode)
            Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: SafeArea(
              child: !_canSendGroupMessage
                  ? Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Hanya admin yang dapat mengirim pesan ke grup ini',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildReplyBar(),
                        if (_isRecording)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: 'Batalkan rekaman',
                                  onPressed: () => _toggleRecording(cancelOnly: true),
                                ),
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatRecordingDuration(_recordingDuration),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Merekam audio...',
                                    style: TextStyle(color: Colors.black54, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                CircleAvatar(
                                  backgroundColor: primaryColor,
                                  radius: 18,
                                  child: IconButton(
                                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                                    tooltip: 'Kirim Voice Note',
                                    onPressed: () => _toggleRecording(cancelOnly: false),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.attach_file, color: Colors.grey),
                                onPressed: _showAttachmentModal,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  decoration: InputDecoration(
                                    hintText: 'Ketik pesan...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendMessage(),
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
                                  onTap: () => _toggleRecording(cancelOnly: false),
                                  child: const CircleAvatar(
                                    backgroundColor: primaryColor,
                                    child: Icon(
                                      Icons.mic,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(Map<String, dynamic> msg) {
    if (msg['status'] == 'pending') {
      return const Icon(
        Icons.access_time,
        size: 12,
        color: Colors.white70,
      );
    }

    final isRead = msg['is_read'] == 1 || msg['is_read'] == true || msg['read'] == true || msg['read'] == 1;
    final isDelivered = msg['is_delivered'] == 1 || msg['is_delivered'] == true || isRead;

    if (isRead) {
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Colors.lightBlueAccent,
      );
    } else if (isDelivered) {
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Colors.white70,
      );
    } else {
      return const Icon(
        Icons.done,
        size: 12,
        color: Colors.white70,
      );
    }
  }

  Future<void> _checkAndMarkUndeliveredMessages(List<dynamic> msgs) async {
    String? currentUserId = _myUserId;
    if (currentUserId == null) {
      final prefs = await SharedPreferences.getInstance();
      currentUserId = prefs.getString('user_id');
      _myUserId = currentUserId;
    }

    final undeliveredIds = <int>[];
    for (var m in msgs) {
      if (m['sender_id'].toString() != currentUserId) {
        final isDelivered = m['is_delivered'];
        if (isDelivered == 0 || isDelivered == false || isDelivered == null) {
          final rawId = m['id'];
          final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
          if (id != null) undeliveredIds.add(id);
        }
      }
    }

    if (undeliveredIds.isNotEmpty) {
      ApiService.markMessagesAsDelivered(widget.roomId, messageIds: undeliveredIds);

      if (_socket != null && _socket!.connected && currentUserId != null) {
        _socket!.emit('message:delivered', {
          'roomId': widget.roomId,
          'userId': currentUserId,
          'messageIds': undeliveredIds,
        });
      }
    }
  }
}


class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const SwipeToReply({Key? key, required this.child, required this.onReply}) : super(key: key);

  @override
  _SwipeToReplyState createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _controller.addListener(() {
      setState(() {
        _dragExtent = _controller.value * _dragExtent;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        if (details.primaryDelta! > 0) {
          setState(() {
            _dragExtent += details.primaryDelta!;
            if (_dragExtent > 60.0) _dragExtent = 60.0;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_dragExtent >= 40.0) {
          widget.onReply();
        }
        _controller.reverse(from: 1.0).then((_) {
          _controller.value = 0.0;
          setState(() {
            _dragExtent = 0.0;
          });
        });
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dragExtent > 0)
            Positioned(
              left: 16.0,
              child: Opacity(
                opacity: (_dragExtent / 40.0).clamp(0.0, 1.0),
                child: const Icon(Icons.reply, color: Colors.grey),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
