import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import 'store_dashboard_screen.dart';

class RegisterStoreScreen extends StatefulWidget {
  const RegisterStoreScreen({super.key});

  @override
  _RegisterStoreScreenState createState() => _RegisterStoreScreenState();
}

class _RegisterStoreScreenState extends State<RegisterStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _nikController = TextEditingController();
  
  File? _ktpPhoto;
  File? _ownerPhoto;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(bool isKtp) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        if (isKtp) {
          _ktpPhoto = File(image.path);
        } else {
          _ownerPhoto = File(image.path);
        }
      });
    }
  }

  void _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_ktpPhoto == null || _ownerPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto KTP dan Foto Diri wajib diunggah!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final res = await ApiService.registerStore(
      _storeNameController.text,
      _fullNameController.text,
      _nikController.text,
      _ktpPhoto!.path,
      _ownerPhoto!.path,
    );

    setState(() {
      _isLoading = false;
    });

    if (res['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pendaftaran berhasil! Menunggu persetujuan admin.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const StoreDashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Gagal mendaftar toko')),
      );
    }
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _fullNameController.dispose();
    _nikController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buka Toko Gratis'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(key: _formKey, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mulai berjualan sekarang!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _storeNameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Toko',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Nama toko wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Lengkap Sesuai KTP',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Nama lengkap wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nikController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nomor Induk Kependudukan (NIK)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty ? 'NIK wajib diisi' : null,
              ),
              const SizedBox(height: 24),
              const Text('Foto KTP', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _pickImage(true),
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    image: _ktpPhoto != null
                        ? DecorationImage(image: FileImage(_ktpPhoto!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _ktpPhoto == null
                      ? const Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.upload_file, size: 40, color: Colors.grey),
                            Text('Ketuk untuk mengunggah Foto KTP')
                          ],
                        ))
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              const Text('Foto Diri Beserta KTP', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _pickImage(false),
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    image: _ownerPhoto != null
                        ? DecorationImage(image: FileImage(_ownerPhoto!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _ownerPhoto == null
                      ? const Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.face, size: 40, color: Colors.grey),
                            Text('Ketuk untuk mengunggah Foto Diri')
                          ],
                        ))
                      : null,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitRegister,
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Daftar Sekarang', style: TextStyle(fontSize: 16)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
