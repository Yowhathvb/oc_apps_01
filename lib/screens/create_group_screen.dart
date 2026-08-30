import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  final String myUserId;

  const CreateGroupScreen({super.key, required this.myUserId});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _selectedPhones = {};
  final TextEditingController _groupNameController = TextEditingController();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  String _normalizePhone(String? p) {
    if (p == null) return '';
    String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (num.startsWith('62')) {
      return '0${num.substring(2)}';
    }
    return num;
  }

  Future<void> _fetchContacts() async {
    try {
      final localContacts = await DatabaseHelper().getContacts();
      setState(() {
        _contacts = localContacts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama grup tidak boleh kosong')),
      );
      return;
    }

    if (_selectedPhones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 kontak')),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    List<String> userIds = [];
    
    // Find user IDs for selected phones
    for (String phone in _selectedPhones) {
      final res = await ApiService.findUserByPhone(phone);
      if (res['success'] && res['data'] != null && res['data']['id'] != null) {
        userIds.add(res['data']['id'].toString());
      }
    }

    if (userIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat menemukan pengguna dari kontak yang dipilih')),
        );
        setState(() {
          _isCreating = false;
        });
      }
      return;
    }

    // Call create group API
    final createRes = await ApiService.createGroupChat(
      _groupNameController.text.trim(),
      userIds,
    );

    if (!mounted) return;

    if (createRes['success']) {
      final groupId = createRes['groupId'].toString();
      
      // Close Create Group screen
      Navigator.pop(context);
      
      // Open Chat Screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            roomId: groupId,
            otherUserName: _groupNameController.text.trim(),
            otherUserPhone: '',
            isGroup: true,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(createRes['message'] ?? 'Gagal membuat grup')),
      );
      setState(() {
        _isCreating = false;
      });
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Baru'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: TextField(
                        controller: _groupNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Grup',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.group),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pilih Kontak (${_selectedPhones.length} dipilih)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ),
                    Expanded(
                      child: _contacts.isEmpty
                          ? const Center(child: Text('Tidak ada kontak tersimpan'))
                          : ListView.builder(
                              itemCount: _contacts.length,
                              itemBuilder: (context, index) {
                                final contact = _contacts[index];
                                final phone = _normalizePhone(contact['phone_number'].toString());
                                final isSelected = _selectedPhones.contains(phone);

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? Colors.green : Colors.blue.shade100,
                                    child: isSelected
                                        ? const Icon(Icons.check, color: Colors.white)
                                        : Text(
                                            contact['saved_name'].toString().substring(0, 1).toUpperCase(),
                                            style: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                  title: Text(contact['saved_name']),
                                  subtitle: Text(phone),
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedPhones.remove(phone);
                                      } else {
                                        _selectedPhones.add(phone);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: _selectedPhones.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              onPressed: _isCreating ? null : _createGroup,
              child: _isCreating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.arrow_forward),
            )
          : null,
    );
  }
}
