import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kebijakan Privasi'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kebijakan Privasi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
            ),
            SizedBox(height: 16),
            Text(
              'Di Digital Space Nusantara, kami sangat menghargai privasi Anda. Kebijakan ini menjelaskan bagaimana kami mengumpulkan, menggunakan, dan melindungi informasi pribadi Anda saat menggunakan aplikasi Our Chat.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              '1. Informasi yang Kami Kumpulkan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Kami dapat mengumpulkan informasi seperti nama, nomor telepon, alamat email, daftar kontak (dengan persetujuan), serta data penggunaan untuk meningkatkan kualitas layanan kami.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              '2. Penggunaan Informasi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Data Anda digunakan untuk memfasilitasi komunikasi antar pengguna, menyediakan dukungan pelanggan, mendeteksi penipuan, dan mengoptimalkan kinerja aplikasi.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              '3. Keamanan Data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Kami menerapkan standar keamanan industri untuk melindungi data pribadi Anda dari akses tanpa izin. Kami tidak menjual informasi Anda kepada pihak ketiga manapun.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 32),
            Text(
              'Terakhir Diperbarui: 29 Agustus 2026',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
