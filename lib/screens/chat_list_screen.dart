import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/api_service.dart';
import '../services/database_helper.dart';
import 'chat_screen.dart';
import 'add_contact_screen.dart';
import 'create_group_screen.dart';
import 'contact_info_screen.dart';
import '../services/call_manager.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _mergedList = [];
  bool _isLoading = true;
  String? _error;
  String? _myUserId;
  io.Socket? _socket;
  String _searchQuery = '';
  Set<String> _selectedChats = {};

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedChats.contains(id)) {
        _selectedChats.remove(id);
      } else {
        _selectedChats.add(id);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
    _initSocket();
  }

  Future<void> _initSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null) return;

    _socket = io.io(ApiService.chatSocketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('subscribeRooms', userId);
    });

    _socket!.on('rooms:update', (data) {
      if (data is Map && data['roomId'] != null) {
        final roomId = data['roomId'].toString();
        final senderId = data['senderId']?.toString();
        // HANYA tandai delivered jika pesan dikirim oleh lawan bicara (bukan oleh diri sendiri)
        if (senderId != null && _myUserId != null && senderId != _myUserId) {
          ApiService.markMessagesAsDelivered(roomId);
          if (_socket != null && _socket!.connected) {
            _socket!.emit('message:delivered', {
              'roomId': roomId,
              'userId': _myUserId,
            });
          }
        }
      }
      // Refresh list chat saat ada pesan baru masuk ke salah satu room kita
      _fetchData(isPolling: true);
    });

    _socket!.on('messages:delivered', (_) {
      _fetchData(isPolling: true);
    });

    _socket!.on('messages:read', (_) {
      _fetchData(isPolling: true);
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  String _normalizePhone(String? p) {
    if (p == null) return '';
    String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (num.startsWith('62')) {
      return '0${num.substring(2)}';
    }
    return num;
  }

  Future<void> _fetchData({bool isPolling = false}) async {
    if (!isPolling && _mergedList.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _myUserId = prefs.getString('user_id');

      // 1. Fetch Local Contacts
      final localContacts = await DatabaseHelper().getContacts();

      // 2. Fetch API Rooms
      final apiResult = await ApiService.getChatRooms();
      List<dynamic> apiRooms = [];
      if (apiResult['success']) {
        apiRooms = apiResult['data']['rooms'] ?? [];
      }

      List<Map<String, dynamic>> combinedList = [];
      List<String> processedPhones = [];

      // Process API rooms first
      for (var room in apiRooms) {
        final roomId = room['id']?.toString();
        final lastSender = room['last_message_sender_id']?.toString();
        final isDelivered = room['last_message_is_delivered'];
        final unreadCount = room['unread_count'] ?? 0;

        // Jika ada pesan dari lawan bicara yang belum delivered, tandai sebagai delivered
        if (roomId != null && _myUserId != null && lastSender != null && lastSender != _myUserId) {
          if (isDelivered == 0 || isDelivered == false || isDelivered == null || unreadCount > 0) {
            ApiService.markMessagesAsDelivered(roomId);
            if (_socket != null && _socket!.connected) {
              _socket!.emit('message:delivered', {
                'roomId': roomId,
                'userId': _myUserId,
              });
            }
          }
        }

        final phone = _normalizePhone(room['other_user_phone']?.toString());
        processedPhones.add(phone);

        // Cek apakah nomor ini ada di daftar kontak lokal
        final localMatch = localContacts.firstWhere(
          (c) => _normalizePhone(c['phone_number'].toString()) == phone,
          orElse: () => <String, dynamic>{},
        );

        String displayName =
            room['other_user_name'] ??
            room['user_1_name'] ??
            room['user_2_name'] ??
            phone;
        bool isSaved = false;

        if (localMatch.isNotEmpty) {
          displayName = localMatch['saved_name'];
          isSaved = true;
        }

        final isRead = room['last_message_is_read'] == 1 || room['last_message_is_read'] == true || room['last_message_read'] == true;

        combinedList.add({
          'phone': phone,
          'display_name': displayName,
          'last_message': room['last_message'] ?? 'Belum ada pesan',
          'last_message_time': room['last_message_time'],
          'last_message_sender_id': lastSender,
          'last_message_is_delivered': isDelivered,
          'last_message_is_read': isRead,
          'unread_count': unreadCount,
          'room_id': room['id'].toString(),
          'is_saved': isSaved,
          'is_group': room['isGroup'] == true || room['is_group'] == true || room['type'] == 'group',
          'profile_pic': room['other_user_profile_pic'] ?? room['profile_pic'],
          'is_registered': true,
        });
      }

      // Add saved contacts that don't have a chat room yet
      for (var contact in localContacts) {
        final phone = _normalizePhone(contact['phone_number'].toString());
        final savedName = contact['saved_name'];
        final isRegistered = contact['is_registered'] == 1;

        if (!processedPhones.contains(phone)) {
          combinedList.add({
            'phone': phone,
            'display_name': savedName,
            'last_message': isRegistered ? 'Belum ada pesan' : 'Kontak ini belum terdaftar',
            'last_message_time': null,
            'last_message_sender_id': null,
            'last_message_is_delivered': null,
            'last_message_is_read': false,
            'unread_count': 0,
            'room_id': null,
            'is_saved': true,
            'is_group': false,
            'profile_pic': null,
            'is_registered': isRegistered,
          });
        }
      }

      // 3. Fetch Pinned Chats
      final pinnedChatsResult = await DatabaseHelper().getPinnedChats();
      final Map<String, int> pinnedChatsMap = {
        for (var p in pinnedChatsResult) p['id'] as String: p['pinned_at'] as int
      };

      for (var i = 0; i < combinedList.length; i++) {
        final item = combinedList[i];
        final id = item['room_id']?.toString() ?? item['phone']?.toString() ?? '';
        if (pinnedChatsMap.containsKey(id)) {
          item['is_pinned'] = true;
          item['pinned_at'] = pinnedChatsMap[id];
        } else {
          item['is_pinned'] = false;
          item['pinned_at'] = 0;
        }
      }

      // Sort by time (descending), nulls last, but pinned chats go first
      combinedList.sort((a, b) {
        // Pinned goes first
        if (a['is_pinned'] && !b['is_pinned']) return -1;
        if (!a['is_pinned'] && b['is_pinned']) return 1;
        
        // If both are pinned, sort by pinned_at DESC (higher timestamp first)
        if (a['is_pinned'] && b['is_pinned']) {
          final pA = a['pinned_at'] as int;
          final pB = b['pinned_at'] as int;
          return pB.compareTo(pA);
        }

        if (a['last_message_time'] == null && b['last_message_time'] == null) {
          return 0;
        }
        if (a['last_message_time'] == null) return 1;
        if (b['last_message_time'] == null) return -1;
        final dateA = DateTime.parse(a['last_message_time']);
        final dateB = DateTime.parse(b['last_message_time']);
        return dateB.compareTo(dateA);
      });

      setState(() {
        _mergedList = combinedList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return '';
    }
  }

  Widget _buildLastMessageStatusIcon(Map<String, dynamic> item) {
    final isRead = item['last_message_is_read'] == true || item['last_message_is_read'] == 1;
    final isDelivered = item['last_message_is_delivered'] == 1 || item['last_message_is_delivered'] == true || isRead;

    if (isRead) {
      return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    } else if (isDelivered) {
      return const Icon(Icons.done_all, size: 14, color: Colors.grey);
    } else {
      return const Icon(Icons.done, size: 14, color: Colors.grey);
    }
  }

  Future<void> _handleChatTap(Map<String, dynamic> item) async {
    if (item['room_id'] != null) {
      // Room already exists, open directly
      _navigateToChat(item['room_id'], item['display_name'], item['phone'], item['is_group'] ?? false, item['profile_pic']);
    } else {
      // Room belum aktif di server, buka langsung dengan local_room_id pre-generated
      final phone = item['phone']?.toString() ?? '';
      String? localRoomId = item['local_room_id']?.toString();
      if (localRoomId == null || localRoomId.isEmpty) {
        localRoomId = await DatabaseHelper().getLocalRoomId(phone);
      }
      if (localRoomId == null || localRoomId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final myUsername = prefs.getString('username') ?? _myUserId ?? 'user';
        localRoomId = DatabaseHelper.generateUniqueRoomId(myUsername);
        await DatabaseHelper().saveContact(
          phone,
          item['display_name'] ?? phone,
          isRegistered: true,
          localRoomId: localRoomId,
        );
      }
      _navigateToChat(localRoomId, item['display_name'] ?? phone, phone, false, item['profile_pic']);
    }
  }

  void _navigateToChat(String roomId, String displayName, String otherPhone, [bool isGroup = false, String? profilePic]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          roomId: roomId,
          otherUserName: displayName,
          otherUserPhone: otherPhone,
          profilePic: profilePic,
          isGroup: isGroup,
        ),
      ),
    ).then((_) {
      _fetchData();
    });
  }

  void _showProfilePopup(BuildContext context, Map<String, dynamic> item) {
    final isGroup = item['is_group'] == true;
    final heroTag = 'profile_pic_hero_${isGroup ? 'group_${item['room_id']}' : (item['phone'] ?? item['room_id'])}';
    
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) {
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Material(
              color: Colors.transparent,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, // Absorb taps on the card itself so it doesn't close
                    child: ScaleTransition(
                      scale: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                      ),
                    child: FadeTransition(
                      opacity: animation,
                      child: Container(
                        width: 320,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 25,
                              spreadRadius: 5,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header Image with Hero
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                _showFullImageDialog(context, item, heroTag);
                              },
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                              child: Hero(
                                tag: heroTag,
                                child: Container(
                                  width: 320,
                                  height: 250,
                                  decoration: BoxDecoration(
                                    color: (item['profile_pic'] != null && item['profile_pic'].toString().isNotEmpty) 
                                        ? Colors.white 
                                        : isGroup
                                            ? Colors.orange.shade100
                                            : (item['is_saved'] == true ? Colors.green.shade100 : Colors.blue.shade100),
                                    image: (item['profile_pic'] != null && item['profile_pic'].toString().isNotEmpty)
                                        ? DecorationImage(
                                            image: NetworkImage(ApiService.getServerUrl(item['profile_pic'])),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: (item['profile_pic'] == null || item['profile_pic'].toString().isEmpty)
                                      ? Center(
                                          child: isGroup
                                              ? Icon(Icons.group_rounded, size: 90, color: Colors.orange.shade800)
                                              : Text(
                                                  (item['display_name'] ?? '?').isNotEmpty 
                                                      ? item['display_name'].substring(0, 1).toUpperCase() 
                                                      : '?',
                                                  style: TextStyle(
                                                    fontSize: 100,
                                                    color: item['is_saved'] == true
                                                        ? Colors.green.shade800
                                                        : const Color(0xFF0F3460),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                        )
                                      : null,
                                  ),
                                ),
                              ),
                            ),
                            // User Info
                            Padding(
                              padding: const EdgeInsets.only(top: 24, bottom: 12, left: 16, right: 16),
                              child: Column(
                                children: [
                                  Text(
                                    item['display_name'] ?? (isGroup ? 'Grup' : 'Unknown'),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F3460),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isGroup ? 'Grup' : (item['phone'] ?? ''),
                                    style: TextStyle(
                                      fontSize: isGroup ? 14 : 15,
                                      color: isGroup ? Colors.orange.shade800 : Colors.grey.shade600,
                                      fontWeight: isGroup ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Actions
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildActionButton(
                                    icon: Icons.chat_bubble_rounded,
                                    label: 'Chat',
                                    color: Colors.blueAccent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      _handleChatTap(item);
                                    },
                                  ),
                                  _buildActionButton(
                                    icon: Icons.call_rounded,
                                    label: 'Voice',
                                    color: Colors.green,
                                    onTap: () {
                                      Navigator.pop(context);
                                      final phone = item['phone']?.toString() ?? '';
                                      final name = item['display_name']?.toString() ?? (isGroup ? 'Grup' : phone);
                                      final roomId = item['room_id']?.toString();
                                      CallManager.instance.startCall(
                                        phone,
                                        name,
                                        false,
                                        groupId: isGroup ? roomId : null,
                                      );
                                    },
                                  ),
                                  _buildActionButton(
                                    icon: Icons.videocam_rounded,
                                    label: 'Video',
                                    color: Colors.teal,
                                    onTap: () {
                                      Navigator.pop(context);
                                      final phone = item['phone']?.toString() ?? '';
                                      final name = item['display_name']?.toString() ?? (isGroup ? 'Grup' : phone);
                                      final roomId = item['room_id']?.toString();
                                      CallManager.instance.startCall(
                                        phone,
                                        name,
                                        true,
                                        groupId: isGroup ? roomId : null,
                                      );
                                    },
                                  ),
                                  _buildActionButton(
                                    icon: Icons.info_outline_rounded,
                                    label: 'Info',
                                    color: Colors.grey.shade700,
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          transitionDuration: const Duration(milliseconds: 320),
                                          reverseTransitionDuration: const Duration(milliseconds: 280),
                                          pageBuilder: (context, animation, secondaryAnimation) => ContactInfoScreen(
                                            phone: item['phone']?.toString() ?? '',
                                            displayName: item['display_name'],
                                            profilePic: item['profile_pic'],
                                            roomId: item['room_id']?.toString(),
                                            isGroup: item['is_group'] == true,
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
                                      ).then((_) {
                                        _fetchData();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ), // Container
                    ), // FadeTransition
                  ), // ScaleTransition
                ), // GestureDetector (inner)
              ), // Center
            ), // BackdropFilter
          ), // Material
        ); // GestureDetector (outer)
      },
      ),
    );
  }

  void _showFullImageDialog(BuildContext context, Map<String, dynamic> item, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          final hasImage = item['profile_pic'] != null && item['profile_pic'].toString().isNotEmpty;
          
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            extendBodyBehindAppBar: true,
            body: Center(
              child: Hero(
                tag: heroTag,
                child: hasImage 
                  ? Image.network(
                      ApiService.getServerUrl(item['profile_pic']), 
                      fit: BoxFit.contain,
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.network(
                              '${ApiService.getServerUrl(item['profile_pic'])}?size=360',
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                            const CircularProgressIndicator(color: Colors.white),
                          ],
                        );
                      },
                    )
                  : Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: item['is_saved'] == true ? Colors.green.shade100 : Colors.blue.shade100,
                      child: Center(
                        child: Text(
                          (item['display_name'] ?? '?').isNotEmpty 
                              ? item['display_name'].substring(0, 1).toUpperCase() 
                              : '?',
                          style: TextStyle(
                            fontSize: 150,
                            color: item['is_saved'] == true
                                ? Colors.green.shade800
                                : const Color(0xFF0F3460),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    final filteredList = _mergedList.where((item) {
      final name = (item['display_name'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase().trim();
      return name.contains(query);
    }).toList();

    final isSelectionMode = _selectedChats.isNotEmpty;

    // Check if all selected items are already pinned
    bool allSelectedArePinned = false;
    if (isSelectionMode) {
      final selectedItems = _mergedList.where((item) {
        final id = item['room_id']?.toString() ?? item['phone']?.toString() ?? '';
        return _selectedChats.contains(id);
      }).toList();
      allSelectedArePinned = selectedItems.isNotEmpty && 
          selectedItems.every((item) => item['is_pinned'] == true);
    }

    return Scaffold(
      appBar: isSelectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedChats.clear();
                  });
                },
              ),
              title: Text('${_selectedChats.length} Terpilih'),
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                IconButton(
                  icon: allSelectedArePinned 
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.push_pin),
                            Transform.rotate(
                              angle: -0.8,
                              child: Container(
                                width: 2,
                                height: 22,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : const Icon(Icons.push_pin),
                  tooltip: allSelectedArePinned ? 'Batal Sematkan' : 'Sematkan',
                  onPressed: () async {
                    for (var id in _selectedChats) {
                      if (allSelectedArePinned) {
                        await DatabaseHelper().unpinChat(id);
                      } else {
                        await DatabaseHelper().pinChat(id);
                      }
                    }
                    setState(() => _selectedChats.clear());
                    _fetchData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.volume_off),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur Bisukan belum tersedia')));
                    setState(() => _selectedChats.clear());
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.archive),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur Arsipkan belum tersedia')));
                    setState(() => _selectedChats.clear());
                  },
                ),
              ],
            )
          : AppBar(
              title: _searchQuery.isNotEmpty 
                  ? TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Cari obrolan...',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    )
                  : const Text('Chats'),
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                IconButton(
                  icon: Icon(_searchQuery.isNotEmpty ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      if (_searchQuery.isNotEmpty) {
                        _searchQuery = '';
                      } else {
                        _searchQuery = ' ';
                      }
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.group_add),
                  onPressed: () {
                    if (_myUserId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateGroupScreen(myUserId: _myUserId!),
                        ),
                      ).then((_) => _fetchData());
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User ID tidak ditemukan. Harap tunggu.')),
                      );
                    }
                  },
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $_error'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchData,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : filteredList.isEmpty
          ? const Center(child: Text('Belum ada obrolan atau kontak.'))
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView.builder(
                itemCount: filteredList.length,
                itemBuilder: (context, index) {
                  final item = filteredList[index];
                  final timeStr = _formatTime(item['last_message_time']);
                  final itemId = item['room_id']?.toString() ?? item['phone']?.toString() ?? '';
                  final isSelected = _selectedChats.contains(itemId);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    color: isSelected ? primaryColor.withOpacity(0.12) : Colors.transparent,
                    child: Material(
                      color: Colors.transparent,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          splashColor: const Color(0xFF0F3460).withOpacity(0.15),
                          highlightColor: Colors.black.withOpacity(0.08),
                        ),
                        child: ListTile(
                          splashColor: const Color(0xFF0F3460).withOpacity(0.15),
                          focusColor: Colors.black.withOpacity(0.06),
                          hoverColor: Colors.black.withOpacity(0.04),
                          onLongPress: item['is_registered'] == false ? null : () {
                            _toggleSelection(itemId);
                          },
                          leading: Stack(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (_selectedChats.isNotEmpty) {
                                    _toggleSelection(itemId);
                                    return;
                                  }
                                  _showProfilePopup(context, item);
                                },
                                child: Hero(
                                  tag: 'profile_pic_hero_${item['is_group'] == true ? 'group_${item['room_id']}' : (item['phone'] ?? item['room_id'])}',
                                  child: CircleAvatar(
                                    backgroundColor: item['is_group'] == true 
                                        ? Colors.orange.shade100
                                        : item['is_saved']
                                            ? Colors.green.shade100
                                            : Colors.blue.shade100,
                                    backgroundImage: (item['profile_pic'] != null && item['profile_pic'].toString().isNotEmpty) 
                                        ? NetworkImage(ApiService.getServerUrl(item['profile_pic'])) 
                                        : null,
                                    child: (item['profile_pic'] != null && item['profile_pic'].toString().isNotEmpty) 
                                        ? null 
                                        : item['is_group'] == true
                                            ? Icon(Icons.group, color: Colors.orange.shade800)
                                            : Text(
                                                (item['display_name'] ?? '?').isNotEmpty 
                                                    ? item['display_name'].substring(0, 1).toUpperCase() 
                                                    : '?',
                                                style: TextStyle(
                                                  color: item['is_saved']
                                                      ? Colors.green.shade800
                                                      : primaryColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: AnimatedScale(
                                  scale: isSelected ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.elasticOut,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['display_name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item['is_pinned'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.push_pin, size: 14, color: Colors.grey),
                                ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              if (item['last_message_sender_id'] != null &&
                                  item['last_message_sender_id'].toString() == _myUserId &&
                                  (item['last_message'] ?? '').toString().isNotEmpty &&
                                  item['last_message'] != 'Belum ada pesan' &&
                                  item['last_message'] != 'Kontak ini belum terdaftar' &&
                                  item['last_message'] != 'Pesan ini telah ditarik') ...[
                                _buildLastMessageStatusIcon(item),
                                const SizedBox(width: 4),
                              ],
                              if (item['last_message'] == 'Pesan ini telah ditarik') ...[
                                Icon(Icons.block_rounded, size: 13, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  item['last_message'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: (item['unread_count'] ?? 0) > 0 ? Colors.black87 : Colors.grey.shade600,
                                    fontWeight: (item['unread_count'] ?? 0) > 0 ? FontWeight.w600 : FontWeight.normal,
                                    fontStyle: item['last_message'] == 'Pesan ini telah ditarik' ? FontStyle.italic : FontStyle.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: item['is_registered'] == false
                              ? TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Fitur undang belum tersedia')),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Undang', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        color: (item['unread_count'] ?? 0) > 0 ? const Color(0xFF0F3460) : Colors.grey,
                                        fontSize: 12,
                                        fontWeight: (item['unread_count'] ?? 0) > 0 ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if ((item['unread_count'] ?? 0) > 0) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade600,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                        child: Center(
                                          child: Text(
                                            '${item['unread_count']}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                          onTap: item['is_registered'] == false 
                              ? null 
                              : () {
                                  if (_selectedChats.isNotEmpty) {
                                    _toggleSelection(itemId);
                                  } else {
                                    _handleChatTap(item);
                                  }
                                },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddContactScreen()),
          );
          // Selalu refresh setelah kembali dari tambah kontak
          _fetchData();
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
