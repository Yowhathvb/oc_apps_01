import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';
import 'chat_screen.dart';

class SelectContactScreen extends StatefulWidget {
  const SelectContactScreen({super.key});

  @override
  State<SelectContactScreen> createState() => _SelectContactScreenState();
}

class _SelectContactScreenState extends State<SelectContactScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await DatabaseHelper().getContacts();
    setState(() {
      _contacts = contacts;
      _isLoading = false;
    });
  }

  Future<void> _startChat(Map<String, dynamic> contact) async {
    final phone = contact['phone_number']?.toString() ?? '';
    if (phone.isEmpty) return;

    // Ambil atau siapkan local_room_id di database lokal
    String? roomId = contact['local_room_id']?.toString();
    if (roomId == null || roomId.isEmpty) {
      roomId = await DatabaseHelper().getLocalRoomId(phone);
    }
    if (roomId == null || roomId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final myUsername = prefs.getString('username') ?? prefs.getString('user_id') ?? 'user';
      roomId = DatabaseHelper.generateUniqueRoomId(myUsername);
      await DatabaseHelper().saveContact(
        phone,
        contact['saved_name'] ?? phone,
        isRegistered: contact['is_registered'] == 1,
        localRoomId: roomId,
      );
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            roomId: roomId!,
            otherUserName: contact['saved_name'] ?? phone,
            otherUserPhone: phone,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    final filteredContacts = _contacts.where((c) {
      final name = (c['saved_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _searchQuery.isNotEmpty
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Cari kontak...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text('Pilih Kontak'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_searchQuery.isNotEmpty ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_searchQuery.isNotEmpty) {
                  _searchQuery = '';
                } else {
                  _searchQuery = ' '; // trigger search mode
                }
              });
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredContacts.isEmpty
              ? const Center(child: Text('Tidak ada kontak.'))
              : ListView.builder(
                  itemCount: filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = filteredContacts[index];
                    return Theme(
                      data: Theme.of(context).copyWith(
                        splashColor: primaryColor.withOpacity(0.15),
                        highlightColor: Colors.black.withOpacity(0.08),
                      ),
                      child: ListTile(
                        splashColor: primaryColor.withOpacity(0.15),
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(contact['saved_name']),
                        subtitle: Text(contact['phone_number']),
                        onTap: () => _startChat(contact),
                      ),
                    );
                  },
                ),
    );
  }
}
