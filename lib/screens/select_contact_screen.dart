import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final phone = contact['phone_number'];
    final findResult = await ApiService.findUserByPhone(phone);
    
    if (!findResult['success']) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nomor ini belum terdaftar di aplikasi')),
        );
      }
      return;
    }

    final targetUserId = findResult['data']['id'].toString();
    final profilePic = findResult['data']['profile_pic']; // if returned
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id');

    if (myUserId == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final createResult = await ApiService.createOrGetRoom(myUserId, targetUserId);
    if (mounted) Navigator.pop(context);

    if (createResult['success']) {
      final roomId = createResult['chatRoomId'].toString();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            roomId: roomId,
            otherUserName: contact['saved_name'],
            otherUserPhone: phone,
            profilePic: profilePic,
          ),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(createResult['message'])),
        );
      }
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
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person),
                      ),
                      title: Text(contact['saved_name']),
                      subtitle: Text(contact['phone_number']),
                      onTap: () => _startChat(contact),
                    );
                  },
                ),
    );
  }
}
