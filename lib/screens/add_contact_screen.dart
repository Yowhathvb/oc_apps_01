import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  Future<void> _saveContact() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan nomor HP wajib diisi')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Simpan kontak ke database lokal SQLite
      await DatabaseHelper().saveContact(phone, name);

      // 2. Langsung cari user ID dan Room ID di API
      final findResult = await ApiService.findUserByPhone(phone);
      if (findResult['success']) {
        final targetUserId = findResult['data']['id'].toString();
        
        final prefs = await SharedPreferences.getInstance();
        final myUserId = prefs.getString('user_id');

        if (myUserId != null) {
          final createResult = await ApiService.createOrGetRoom(myUserId, targetUserId);
          
          if (createResult['success']) {
            final roomId = createResult['chatRoomId'].toString();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kontak berhasil disimpan')),
              );
              
              // Langsung loncat ke halaman chat!
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    roomId: roomId,
                    otherUserName: name,
                    otherUserPhone: phone,
                  ),
                ),
              );
              return;
            }
          }
        }
      }
      
      // Jika gagal mendapatkan user atau gagal membuat room, tampilkan error yang sebenarnya
      if (mounted) {
        final errorMsg = !findResult['success'] 
            ? findResult['message'] ?? 'User tidak ditemukan'
            : 'Gagal membuat room chat';
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kontak disimpan secara lokal, namun gagal terhubung: $errorMsg')),
        );
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan kontak: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tambah Kontak'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Kontak',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Nomor HP',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Simpan Kontak', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
