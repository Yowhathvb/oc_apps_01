import 'package:flutter/material.dart';
import 'login_screen.dart';

class SuspendScreen extends StatelessWidget {
  final String reason;
  final String? duration;

  const SuspendScreen({super.key, required this.reason, this.duration});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.block,
                color: Colors.red,
                size: 100,
              ),
              const SizedBox(height: 24),
              const Text(
                'Akun Ditangguhkan',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Mohon maaf, akun Anda telah ditangguhkan oleh sistem kami karena:\n\n$reason',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              if (duration != null && duration != 'permanent')
                Text(
                  'Durasi penangguhan: $duration',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (duration == 'permanent')
                const Text(
                  'Akun Anda ditangguhkan secara permanen.',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (Route<dynamic> route) => false,
                    );
                  },
                  child: const Text('Kembali ke Halaman Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
