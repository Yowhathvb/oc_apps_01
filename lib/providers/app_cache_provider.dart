import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../models/story_model.dart';

class AppCacheProvider extends ChangeNotifier {
  List<Map<String, dynamic>> chatRooms = [];
  List<UserStories> allStories = [];
  UserStories? myStories;
  List<dynamic> callHistory = [];
  
  bool isInitialized = false;

  Future<void> initializeData() async {
    try {
      await Future.wait([
        refreshChatRooms().catchError((e) => print('Error chat rooms: $e')),
        refreshStories().catchError((e) => print('Error stories: $e')),
        refreshMyStories().catchError((e) => print('Error my stories: $e')),
        refreshCallHistory().catchError((e) => print('Error calls: $e')),
      ]);
    } catch (e) {
      print('Initialize data error: $e');
    }
    isInitialized = true;
    notifyListeners();
  }

  Future<void> refreshChatRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id');
    if (myUserId == null) return;

    final localContacts = await DatabaseHelper().getContacts();
    final apiResult = await ApiService.getChatRooms();
    
    List<dynamic> apiRooms = [];
    if (apiResult['success']) {
      apiRooms = apiResult['data']['rooms'] ?? [];
    }

    List<Map<String, dynamic>> combinedList = [];
    List<String> processedPhones = [];

    String normalizePhone(String? p) {
      if (p == null) return '';
      String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
      if (num.startsWith('62')) {
        return '0${num.substring(2)}';
      }
      return num;
    }

    for (var room in apiRooms) {
      final isGroup = room['is_group'] == 1;
      if (isGroup) {
        combinedList.add({
          'room_id': room['id'].toString(),
          'display_name': room['name'] ?? 'Grup',
          'phone': '',
          'isGroup': true,
          'is_saved': false,
          'last_message': room['last_message'] ?? '',
          'last_message_time': room['last_message_time'],
          'profile_picture': '',
        });
      } else {
        String otherPhone = room['other_user_phone']?.toString() ?? '';
        String normPhone = normalizePhone(otherPhone);
        
        bool isSaved = false;
        String displayName = otherPhone;

        for (var c in localContacts) {
          if (normalizePhone(c['phone']) == normPhone) {
            isSaved = true;
            displayName = c['name'];
            break;
          }
        }

        if (!isSaved) {
          String otherName = room['user_1_id'].toString() == myUserId 
              ? (room['user_2_name'] ?? '')
              : (room['user_1_name'] ?? '');
          if (otherName.isNotEmpty) {
            displayName = otherName;
          }
        }

        processedPhones.add(normPhone);

        combinedList.add({
          'room_id': room['id'].toString(),
          'display_name': displayName,
          'phone': otherPhone,
          'isGroup': false,
          'is_saved': isSaved,
          'last_message': room['last_message'] ?? '',
          'last_message_time': room['last_message_time'],
          'profile_picture': room['other_user_profile_picture'] ?? '',
        });
      }
    }

    for (var contact in localContacts) {
      if (!processedPhones.contains(normalizePhone(contact['phone']))) {
        combinedList.add({
          'room_id': null,
          'display_name': contact['name'],
          'phone': contact['phone'],
          'isGroup': false,
          'is_saved': true,
          'last_message': '',
          'last_message_time': null,
          'profile_picture': '',
        });
      }
    }

    combinedList.sort((a, b) {
      final aTime = a['last_message_time'];
      final bTime = b['last_message_time'];
      
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      
      final aDate = DateTime.tryParse(aTime.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(bTime.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    chatRooms = combinedList;
    notifyListeners();
  }

  Future<void> refreshStories() async {
    final result = await ApiService.getStories();
    if (result['success']) {
      List<dynamic> usersWithStories = result['data'] ?? [];
      
      final contacts = await DatabaseHelper().getContacts();
      String normalizePhone(String p) {
        String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
        if (num.startsWith('62')) return '0${num.substring(2)}';
        return num;
      }

      for (var user in usersWithStories) {
        String phone = user['phone'] ?? '';
        String normPhone = normalizePhone(phone);
        bool isContact = false;
        String displayName = user['name'] ?? phone;
        for (var contact in contacts) {
          if (normalizePhone(contact['phone'] ?? '') == normPhone) {
            isContact = true;
            displayName = contact['name'];
            break;
          }
        }
        user['is_contact'] = isContact;
        user['display_name'] = displayName;
      }
      
      final parsed = usersWithStories.map((json) => UserStories.fromJson(json)).toList();
      for (var userStory in parsed) {
        userStory.stories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
      allStories = parsed;
      notifyListeners();
    }
  }

  Future<void> refreshMyStories() async {
    final result = await ApiService.getMyStories();
    if (result['success']) {
      final myRawStories = (result['data'] as List).map((json) => Story.fromJson(json)).toList();
      if (myRawStories.isNotEmpty) {
        myStories = UserStories(userId: '', userName: 'Saya', stories: myRawStories);
      } else {
        myStories = null;
      }
      notifyListeners();
    }
  }

  void injectNewStory(dynamic storyData) {
    if (storyData == null) return;
    try {
      final newStory = Story.fromJson(storyData);
      final userId = storyData['userId']?.toString();
      final userName = storyData['userName']?.toString() ?? 'Unknown';

      if (userId == null) return;

      int userIndex = allStories.indexWhere((u) => u.userId == userId);
      if (userIndex != -1) {
        allStories[userIndex].stories.insert(0, newStory); // Add to top of the user's list
      } else {
        allStories.insert(0, UserStories(
          userId: userId,
          userName: userName,
          stories: [newStory]
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to inject story: $e');
    }
  }

  Future<void> refreshCallHistory() async {
    final result = await ApiService.getCallHistory();
    if (result['success']) {
      callHistory = result['data'] ?? [];
      notifyListeners();
    }
  }
}
