import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import '../services/call_manager.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'store_dashboard_screen.dart';
import '../services/api_service.dart';
import 'about_screen.dart';
import 'profile_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _name = 'User';
  String _phone = '';
  String _username = '';
  String _profilePicture = '';
  bool _isLoading = true;
  bool _isNotificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    final isGranted = await NotificationService().checkPermission();
    setState(() {
      _isNotificationEnabled = isGranted;
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Fallback awal dari prefs
    String localName = prefs.getString('user_name') ?? 'User';
    String localPhone = prefs.getString('user_phone') ?? '';
    String localUsername = prefs.getString('username') ?? '';
    String localProfilePic = prefs.getString('profile_picture') ?? '';

    setState(() {
      _name = localName;
      _phone = localPhone;
      _username = localUsername;
      _profilePicture = localProfilePic;
    });

    // Coba ambil data terbaru dari API
    final res = await ApiService.getMyProfile();
    if (res['success'] && res['data'] != null && res['data']['user'] != null) {
      final user = res['data']['user'];
      setState(() {
        _name = user['name'] ?? localName;
        _phone = user['phone'] ?? localPhone;
        _username = user['username'] ?? localUsername;
        _profilePicture = user['profile_picture'] ?? localProfilePic;
        _isLoading = false;
      });
      // Simpan ke prefs agar sinkron
      await prefs.setString('user_name', _name);
      await prefs.setString('user_phone', _phone);
      await prefs.setString('username', _username);
      await prefs.setString('profile_picture', _profilePicture);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Disconnect call socket
      CallManager.instance.logout();
      FlutterCallkitIncoming.endAllCalls();

      // Hapus data sesi lokal
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user_id');
      await prefs.remove('user_name');
      await prefs.remove('user_phone');
      await prefs.remove('username');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildMenuItem(IconData icon, String title, String subtitle, {Color iconColor = Colors.white, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, size: 28, color: iconColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap ?? () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title - Segera Hadir!')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('⋮ Lainnya'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profil User
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfileScreen()),
                      ).then((_) => _loadUserData());
                    },
                    child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: primaryColor,
                          backgroundImage: _profilePicture.isNotEmpty 
                              ? CachedNetworkImageProvider('${ApiService.baseUrl.replaceAll('/api/v1', '')}/uploads/profiles/$_profilePicture')
                              : null,
                          child: _profilePicture.isEmpty 
                              ? Text(
                                  _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_username.isNotEmpty)
                                Text(
                                  '@$_username',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              Text(
                                _phone,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ), // End of GestureDetector

                  // Menu Unggulan
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text(
                      'UNGGULAN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  _buildMenuItem(Icons.apps, 'Mini Apps', 'Akses aplikasi tambahan', iconColor: Colors.blue),
                  _buildMenuItem(
                    Icons.storefront, 
                    'Admin Marketplace', 
                    'Kelola toko dan pesanan', 
                    iconColor: Colors.orange,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const StoreDashboardScreen()));
                    },
                  ),
                  _buildMenuItem(Icons.payment, 'Our Pay', 'Ringkasan keuangan', iconColor: Colors.green),

                  // Menu Umum
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text(
                      'UMUM',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  _buildMenuItem(Icons.settings, 'Pengaturan', 'Atur preferensi Anda', iconColor: Colors.black54),
                  _buildMenuItem(
                    Icons.info, 
                    'Tentang Aplikasi', 
                    'Versi, pengembang, dan lisensi', 
                    iconColor: Colors.blue, 
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutScreen()));
                    }
                  ),
                  _buildMenuItem(Icons.lock, 'Privasi & Keamanan', 'Kelola privasi akun', iconColor: Colors.black54),
                  _buildMenuItem(Icons.storage, 'Penyimpanan & Data', 'Kelola data dan cache', iconColor: Colors.black54),
                  
                  // Notification Settings Section
                  Container(
                    color: Colors.black.withValues(alpha: 0.02),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.notifications, size: 28, color: Colors.black54),
                          title: const Text('Notifikasi Push', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Aktifkan notifikasi untuk aplikasi', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          value: _isNotificationEnabled,
                          activeThumbColor: primaryColor,
                          onChanged: (bool value) async {
                            if (value) {
                              final granted = await NotificationService().requestPermission();
                              setState(() {
                                _isNotificationEnabled = granted;
                              });
                              if (!granted && mounted) {
                                // Tampilkan dialog untuk buka setting OS karena ditolak permanen
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Izin Ditolak'),
                                    content: const Text('Anda telah menolak izin notifikasi secara permanen. Silakan buka Pengaturan HP Anda untuk mengizinkannya secara manual.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          openAppSettings();
                                        },
                                        child: const Text('Buka Pengaturan'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            } else {
                              // Untuk mematikan secara programatik dari app tidak bisa sepenuhnya di Android 13+,
                              // Tapi kita bisa memberikan instruksi ke pengguna atau hanya menyimpannya di preferensi lokal jika backend kita mendengarkan status ini.
                              // Untuk saat ini kita arahkan ke pengaturan sistem.
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Matikan Notifikasi'),
                                  content: const Text('Untuk mematikan notifikasi, silakan nonaktifkan melalui Pengaturan sistem HP Anda.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Tutup'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        openAppSettings();
                                      },
                                      child: const Text('Pengaturan Sistem'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                        ),
                        if (_isNotificationEnabled)
                          Padding(
                            padding: const EdgeInsets.only(left: 72, right: 20, bottom: 10),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                NotificationService().showTestNotification();
                              },
                              icon: const Icon(Icons.send, size: 16),
                              label: const Text('Uji Notifikasi Lokal'),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: primaryColor,
                                backgroundColor: Colors.blue.shade50,
                                elevation: 0,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  _buildMenuItem(Icons.help_outline, 'Bantuan', 'FAQ dan dukungan', iconColor: Colors.black54),
                  _buildMenuItem(Icons.info_outline, 'Tentang Aplikasi', 'Versi dan informasi', iconColor: Colors.black54),

                  const SizedBox(height: 20),
                  
                  // Logout Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _handleLogout,
                      child: const Text(
                        'Keluar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
