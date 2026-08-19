import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'api_service.dart';

// Channel ID tunggal — harus sama persis dengan channelId di fcmHelper.ts (Next.js)
const String kChatChannelId = 'ourchat_main_channel';
const String kChatChannelName = 'Our Chat Notifications';
const String kChatChannelDesc = 'Notifikasi pesan dan panggilan Our Chat';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
        // Navigasi saat notifikasi diklik bisa ditambahkan di sini
      },
    );

    // KRITIS: Buat Android Notification Channel saat init, bukan hanya saat
    // tombol test ditekan. Tanpa ini, FCM notification dari server akan dibuang
    // oleh Android karena channel belum ada.
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        kChatChannelId,
        kChatChannelName,
        description: kChatChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    print('Notification channel "$kChatChannelId" created/verified.');

    // Konfigurasi FCM
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Minta & simpan token FCM ke server
    try {
      String? token = await messaging.getToken();
      print("FCM Token: $token");
      if (token != null) {
        await ApiService.saveFcmToken(token);
      }
    } catch (e) {
      print("Gagal mengambil FCM Token: $e");
    }

    // Dengarkan pesan foreground — tidak tampilkan popup (user sedang buka app)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Menerima notifikasi foreground: ${message.notification?.title}");
    });

    _isInitialized = true;
  }

  Future<bool> checkPermission() async {
    return await Permission.notification.isGranted;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Dipakai oleh tombol "Cek Notif" di menu More
  Future<void> showTestNotification() async {
    if (!_isInitialized) await init();

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      kChatChannelId,
      kChatChannelName,
      channelDescription: kChatChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id: Random().nextInt(1000),
      title: 'Pemberitahuan Uji Coba',
      body: 'Ini adalah notifikasi lokal dari aplikasi Our Chat Anda!',
      notificationDetails: platformDetails,
    );
  }
}
