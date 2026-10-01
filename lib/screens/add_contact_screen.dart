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
      // 1. Cek apakah nomor ada di API
      final findResult = await ApiService.findUserByPhone(phone);
      final isRegistered = findResult['success'] == true;

      // 2. Simpan kontak ke database lokal SQLite dengan flag is_registered
      await DatabaseHelper().saveContact(phone, name, isRegistered: isRegistered);

      if (isRegistered) {
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
      
      // Jika nomor tidak terdaftar atau gagal membuat room, kita kembali dengan sukses (karena kontak sudah tersimpan lokal)
      if (mounted) {
        if (!isRegistered) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kontak disimpan, namun belum terdaftar di aplikasi')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kontak disimpan, tetapi gagal membuat obrolan')),
          );
        }
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
