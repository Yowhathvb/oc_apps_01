import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/api_service.dart';
import '../services/database_helper.dart';
import 'chat_screen.dart';
import 'add_contact_screen.dart';
import 'create_group_screen.dart';
import 'select_contact_screen.dart';

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

    final uri = Uri.parse(ApiService.baseUrl);
    final socketUrl = '${uri.scheme}://${uri.host}:4000';

    _socket = io.io(socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('subscribeRooms', userId);
    });

    _socket!.on('rooms:update', (data) {
      // Refresh list chat saat ada pesan baru masuk ke salah satu room kita
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

        combinedList.add({
          'phone': phone,
          'display_name': displayName,
          'last_message': room['last_message'] ?? 'Belum ada pesan',
          'last_message_time': room['last_message_time'],
          'room_id': room['id'].toString(),
          'is_saved': isSaved,
          'is_group': room['isGroup'] == true || room['is_group'] == true || room['type'] == 'group',
        });
      }

      // Add saved contacts that don't have a chat room yet
      for (var contact in localContacts) {
        final phone = _normalizePhone(contact['phone_number'].toString());
        final savedName = contact['saved_name'];

        if (!processedPhones.contains(phone)) {
          combinedList.add({
            'phone': phone,
            'display_name': savedName,
            'last_message': 'Belum ada pesan',
            'last_message_time': null,
            'room_id': null,
            'is_saved': true,
            'is_group': false,
          });
        }
      }

      // Sort by time (descending), nulls last
      combinedList.sort((a, b) {
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

  Future<void> _handleChatTap(Map<String, dynamic> item) async {
    if (item['room_id'] != null) {
      // Room already exists, open directly
      _navigateToChat(item['room_id'], item['display_name'], item['phone'], item['is_group'] ?? false, item['profile_pic']);
    } else {
      // Room doesn't exist yet, need to create via API
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final phone = item['phone'];

      // 1. Find user ID by phone
      final findResult = await ApiService.findUserByPhone(phone);
      if (!findResult['success']) {
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal: ${findResult['message']}')),
          );
        }
        return;
      }

      final targetUserId = findResult['data']['id'].toString();

      // 2. Create or Get Room
      final createResult = await ApiService.createOrGetRoom(
        _myUserId!,
        targetUserId,
      );
      if (mounted) Navigator.pop(context); // Close loading

      if (createResult['success']) {
        final newRoomId = createResult['chatRoomId'].toString();
        _navigateToChat(newRoomId, item['display_name'], item['phone']);

        // Refresh list after returning to get updated room_id
        _fetchData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(createResult['message'])));
        }
      }
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    final filteredList = _mergedList.where((item) {
      final name = (item['display_name'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase().trim();
      return name.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
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

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item['is_group'] == true 
                          ? Colors.orange.shade100
                          : item['is_saved']
                              ? Colors.green.shade100
                              : Colors.blue.shade100,
                      child: item['is_group'] == true
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
                    title: Text(
                      item['display_name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      item['last_message'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      timeStr,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    onTap: () => _handleChatTap(item),
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
