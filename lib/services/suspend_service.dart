import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../screens/suspend_screen.dart';
import '../screens/login_screen.dart';
import '../main.dart'; 

class SuspendService {
  static final SuspendService _instance = SuspendService._internal();
  factory SuspendService() => _instance;
  SuspendService._internal();

  io.Socket? _socket;

  Future<void> _handleSuspend(String reason, String? duration) async {
    await ApiService.logout();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => SuspendScreen(reason: reason, duration: duration)),
      (Route<dynamic> route) => false,
    );
  }

  void init() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null) return;

    if (_socket != null) {
      dispose();
    }

    // Cek status saat aplikasi pertama kali dibuka (untuk kasus di mana pengguna disuspend saat offline)
    final authCheck = await ApiService.checkAuth();
    if (authCheck['success'] && authCheck['data']['user'] != null) {
      final user = authCheck['data']['user'];
      if (user['is_suspended'] == true || user['is_suspended'] == 1) {
        await _handleSuspend(user['suspend_reason'] ?? 'Melanggar ketentuan', user['suspend_until']);
        return;
      }
    } else if (authCheck['message'] == 'Unauthorized') {
      await ApiService.logout();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
      return;
    }

    _socket = io.io(ApiService.chatSocketUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .build());

    _socket?.connect();

    _socket?.onConnect((_) {
      _socket?.emit('subscribeRooms', userId);
    });

    _socket?.on('account_suspended', (data) async {
      final reason = data['reason'] ?? 'Melanggar ketentuan';
      final duration = data['duration'];
      await _handleSuspend(reason, duration);
    });
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
  }
}
