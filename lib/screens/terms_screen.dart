import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syarat & Ketentuan'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Syarat & Ketentuan Penggunaan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
            ),
            SizedBox(height: 16),
            Text(
              'Selamat datang di aplikasi Our Chat. Dengan mengunduh, menginstal, atau menggunakan aplikasi ini, Anda menyetujui seluruh syarat dan ketentuan yang berlaku. Harap baca dengan seksama sebelum melanjutkan penggunaan layanan kami.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              '1. Penggunaan Layanan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Layanan ini disediakan oleh Digital Space Nusantara. Anda setuju untuk tidak menggunakan aplikasi ini untuk tujuan ilegal, pelecehan, pelanggaran hak cipta, atau tindakan lain yang merugikan pihak lain.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              '2. Akun dan Keamanan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Anda bertanggung jawab penuh untuk menjaga kerahasiaan akun dan kata sandi Anda. Kami berhak menangguhkan atau menghapus akun yang diduga melanggar kebijakan kami.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              '3. Perubahan Ketentuan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Kami berhak mengubah syarat dan ketentuan ini sewaktu-waktu tanpa pemberitahuan sebelumnya. Penggunaan berkelanjutan atas layanan kami setelah perubahan merupakan bentuk persetujuan Anda.',
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
