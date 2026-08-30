import 'package:flutter/material.dart';
import 'terms_screen.dart';
import 'privacy_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    const accentColor = Color(0xFF4A90E2);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Tentang Aplikasi'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: const BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 50,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Our Chat',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Versi 1.0.0',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Text(
                    'Our Chat adalah aplikasi komunikasi modern yang cepat, aman, dan dapat diandalkan. Dilengkapi dengan fitur pengiriman pesan real-time, panggilan suara dan video, serta pengelolaan grup yang mudah.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildInfoTile(context, Icons.developer_board, 'Pengembang', 'Digital Space Nusantara', accentColor),
                  const Divider(height: 1),
                  _buildInfoTile(context, Icons.email_outlined, 'Hubungi Kami', 'support@ourchat.com', accentColor),
                  const Divider(height: 1),
                  _buildInfoTile(context, Icons.description_outlined, 'Syarat & Ketentuan', 'Ketentuan penggunaan layanan', accentColor, navigateTo: const TermsScreen()),
                  const Divider(height: 1),
                  _buildInfoTile(context, Icons.privacy_tip_outlined, 'Kebijakan Privasi', 'Bagaimana data Anda dilindungi', accentColor, navigateTo: const PrivacyScreen()),
                  
                  const SizedBox(height: 40),
                  const Text(
                    '© 2026 Digital Space Nusantara. All rights reserved.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, IconData icon, String title, String subtitle, Color accentColor, {Widget? navigateTo}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: accentColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.black54),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: () {
        if (navigateTo != null) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => navigateTo));
        }
      },
    );
  }
}
