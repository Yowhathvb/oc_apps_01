import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'home_screen.dart';
import 'chat_list_screen.dart';
import 'call_history_screen.dart';
import 'more_screen.dart';
import 'story_screen.dart';
import 'media_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  final List<Widget> _pages = [
    const ChatListScreen(), // Halaman Chat
    const CallHistoryScreen(), // Halaman Riwayat Panggilan
    const StoryScreen(), // Halaman Status (Story)
    const MediaScreen(), // Halaman Media (Threads-like)
    const Center(child: Text("Marketplace")), // Placeholder Marketplace
    const MoreScreen(), // Halaman Lainnya
  ];

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.call),
            label: 'Calls',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_rounded), // Atau icons.data_usage untuk status
            label: 'Status',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.perm_media_rounded), // Ikon media
            label: 'Media',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront), // Ikon marketplace
            label: 'Market',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz), // Ikon more / settings
            label: 'More',
          ),
        ],
      ),
    );
  }
}
