import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/call_manager.dart';
import 'widgets/call_overlay.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling a background message: ${message.messageId}");

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'ourchat_main_channel',
    'Our Chat Notifications',
    description: 'Notifikasi pesan dan panggilan Our Chat',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  print("Background: channel ensured. Data: ${message.data}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase dengan options yang benar
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Check login session
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getString('session_token') != null;
  
  // Tampilkan UI DULU, baru inisialisasi service di background
  // Ini mencegah layar hitam akibat menunggu koneksi socket/network
  runApp(MainApp(isLoggedIn: isLoggedIn));

  // Inisialisasi service secara non-blocking setelah UI sudah tampil
  if (isLoggedIn) {
    NotificationService().requestPermission().then((_) {
      NotificationService().init();
    });
    CallManager.instance.initSocket();
  }
}

class MainApp extends StatelessWidget {
  final bool isLoggedIn;
  const MainApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(navigatorKey: navigatorKey,
      title: 'Our Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF0F3460),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F3460)),
      ),
      builder: (context, child) {
        return CallOverlay(child: child!);
      },
      home: isLoggedIn ? const MainScreen() : const LoginScreen(),
    );
  }
}

