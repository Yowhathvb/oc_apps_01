import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'custom_gallery_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _name = '';
  String _about = '';
  String _username = '';
  String _phone = '';
  String? _profilePic;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final res = await ApiService.getMyProfile();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          final data = res['data']['user'];
          _name = data['name'] ?? '';
          _about = data['bio'] ?? 'Atur isi Tentang'; // API returns 'bio' instead of 'about'
          if (_about.isEmpty) _about = 'Atur isi Tentang';
          _username = data['username'] ?? '';
          _phone = data['phone'] ?? '';
          _profilePic = data['profile_pic'];
        }
      });
    }
  }

  Future<void> _pickAndCropImage() async {
    final pickedFile = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const CustomGalleryPicker(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutQuart;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
    
    if (pickedFile != null && pickedFile is File) {
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Foto',
            toolbarColor: const Color(0xFF0F3460),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Potong Foto',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (croppedFile != null) {
        _uploadProfilePic(croppedFile.path);
      }
    }
  }

  Future<void> _uploadProfilePic(String path) async {
    setState(() => _isLoading = true);
    final res = await ApiService.uploadProfilePicture(path);
    if (mounted) {
      if (res['success'] == true) {
        setState(() {
          _profilePic = res['data'] != null ? res['data']['profile_pic'] : res['profile_pic']; 
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profil berhasil diperbarui')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Gagal memperbarui foto profil')),
        );
      }
      setState(() => _isLoading = false);
    }
  }


  void _showImageDialog() {
    if (_profilePic == null || _profilePic!.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.black),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteProfilePic();
                  },
                ),
              ],
            ),
            body: Center(
              child: Hero(
                tag: 'profile_pic_hero',
                child: Image.network(
                  ApiService.getServerUrl(_profilePic!),
                  fit: BoxFit.contain,
                  width: double.infinity,
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

  Future<void> _deleteProfilePic() async {
    setState(() => _isLoading = true);
    // Assuming backend will have a DELETE endpoint or updateProfile with null
    try {
      final res = await ApiService.deleteProfilePicture();
      if (res['success'] == true) {
        setState(() {
          _profilePic = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto profil berhasil dihapus')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal menghapus foto')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terjadi kesalahan saat menghapus foto')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editField(String title, String currentValue, int maxLength, Function(String) onSave) async {
    final controller = TextEditingController(text: currentValue);
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F3460),
          title: Text('Masukkan $title', style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            maxLength: maxLength,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterStyle: const TextStyle(color: Colors.black87),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.lightBlue)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.lightBlue)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Colors.black87)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (controller.text.trim().isNotEmpty) {
                  onSave(controller.text.trim());
                }
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.lightBlue)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveProfile(String name, String about) async {
    setState(() => _isLoading = true);
    final res = await ApiService.updateProfile(name, about, null);
    if (mounted) {
      if (res['success'] == true) {
        setState(() {
          _name = name;
          _about = about;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Gagal memperbarui profil')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color subtitleColor = Colors.black87,
  }) {
    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Icon(icon, color: const Color(0xFF0F3460)),
      ),
      title: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: subtitleColor, fontSize: 16, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Colors.white;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Profil'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _showImageDialog,
                          child: Hero(
                            tag: 'profile_pic_hero',
                            child: CircleAvatar(
                              radius: 75,
                              backgroundColor: Colors.grey[800],
                              backgroundImage: _profilePic != null && _profilePic!.isNotEmpty
                                  ? NetworkImage('${ApiService.baseUrl.replaceAll('/api', '')}$_profilePic')
                                  : null,
                              child: _profilePic == null || _profilePic!.isEmpty
                                  ? const Icon(Icons.person, size: 80, color: Colors.black87)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickAndCropImage,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.lightBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildListTile(
                    icon: Icons.person_outline,
                    title: 'Nama',
                    subtitle: _name.isEmpty ? 'Atur isi Nama' : _name,
                    subtitleColor: _name.isEmpty ? Colors.lightBlue : Colors.black87,
                    onTap: () {
                      _editField('Nama', _name.isEmpty ? '' : _name, 25, (val) => _saveProfile(val, _about));
                    },
                  ),
                  _buildListTile(
                    icon: Icons.info_outline,
                    title: 'Tentang',
                    subtitle: _about,
                    subtitleColor: _about == 'Atur isi Tentang' ? Colors.green : Colors.black87,
                    onTap: () {
                      _editField('Tentang', _about == 'Atur isi Tentang' ? '' : _about, 40, (val) => _saveProfile(_name, val));
                    },
                  ),
                  _buildListTile(
                    icon: Icons.alternate_email,
                    title: 'Nama pengguna',
                    subtitle: _username,
                  ),
                  _buildListTile(
                    icon: Icons.phone,
                    title: 'Telepon',
                    subtitle: _phone,
                  ),
                ],
              ),
            ),
    );
  }
}
