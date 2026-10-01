import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

class ApiService {
  static String get baseUrl {
    return dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:3001/api';
  }

  static String get callsSocketUrl {
    final envUrl = dotenv.env['CALLS_SOCKET_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    
    final uri = Uri.parse(baseUrl);
    // Secara default, langsung tembak ke port 4001
    return '${uri.scheme}://${uri.host}:4001';
  }

  static String get chatSocketUrl {
    final envUrl = dotenv.env['CHAT_SOCKET_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    
    final uri = Uri.parse(baseUrl);
    // Secara default, langsung tembak ke port 4000
    return '${uri.scheme}://${uri.host}:4000';
  }

  static String getServerUrl(String path) {
    if (path.startsWith('http')) return path;
    final uri = Uri.parse(baseUrl);
    // Asumsikan base URL formatnya http://host:port/api
    final domain = '${uri.scheme}://${uri.host}:${uri.port}';
    return path.startsWith('/') ? '$domain$path' : '$domain/$path';
  }

  static Future<Map<String, dynamic>> login(String phone, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Save token to shared preferences
        if (data['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('session_token', data['token']);
          if (data['user'] != null && data['user']['id'] != null) {
            await prefs.setString('user_id', data['user']['id'].toString());
          }
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> register(String name, String username, String phone, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'username': username,
          'phone': phone,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        // Save token to shared preferences
        if (data['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('session_token', data['token']);
          if (data['user'] != null && data['user']['id'] != null) {
            await prefs.setString('user_id', data['user']['id'].toString());
          }
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Register failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_token');
    await prefs.remove('user_id');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_token');
  }

  static Future<Map<String, dynamic>> checkAuth() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Unauthorized'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // --- CHAT API ---

  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final sessionToken = prefs.getString('session_token');
    
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    if (userId != null) {
      headers['Cookie'] = 'user_id=$userId';
    }
    if (sessionToken != null) {
      headers['Authorization'] = 'Bearer $sessionToken';
      if (userId != null) {
        headers['Cookie'] = 'user_id=$userId; session_token=$sessionToken';
      } else {
        headers['Cookie'] = 'session_token=$sessionToken';
      }
    }

    return headers;
  }

  static Future<Map<String, dynamic>> getChatRooms() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/chat/rooms'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengambil chat rooms: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getChatMessages(String chatRoomId, {int limit = 30, int offset = 0}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/chat/$chatRoomId/messages?limit=$limit&offset=$offset'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengambil pesan: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendMessage(String chatRoomId, String message, {int? replyToId, String? ciphertext, String? type}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/chat/$chatRoomId/messages'),
        headers: headers,
        body: jsonEncode({'message': message}),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengirim pesan: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadMedia(String chatRoomId, String filePath, String mediaType, {String caption = ''}) async {
    try {
      final headers = await getAuthHeaders();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chat/$chatRoomId/upload-media'));
      request.headers.addAll(headers);
      
      request.fields['mediaType'] = mediaType;
      if (caption.isNotEmpty) {
        request.fields['caption'] = caption;
      }
      
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);
      
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Gagal mengirim media'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> findUserByPhone(String phone) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/users/find'),
        headers: headers,
        body: jsonEncode({'phone': phone}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['user'] != null) {
        return {'success': true, 'data': data['user']};
      } else {
        return {'success': false, 'message': data['error'] ?? 'User tidak ditemukan'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> createOrGetRoom(String userId1, String userId2) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/chat/create-or-get'),
        headers: headers,
        body: jsonEncode({'userId1': userId1, 'userId2': userId2, 'checkOnly': false}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['chatRoomId'] != null) {
        return {'success': true, 'chatRoomId': data['chatRoomId']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Gagal membuat room'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // --- GROUP CHAT API ---

  static Future<Map<String, dynamic>> createGroupChat(String name, List<String> userIds) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/chat/groups'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'userIds': userIds.map((id) => int.tryParse(id) ?? 0).toList(),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'groupId': data['groupId'] ?? data['id']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Gagal membuat grup'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getGroupMessages(String groupId, {int limit = 30, int offset = 0}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/chat/groups/$groupId/messages?limit=$limit&offset=$offset'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengambil pesan grup: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendGroupMessage(String groupId, String message, {int? replyToId, String? ciphertext, String? type}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/chat/groups/$groupId/messages'),
        headers: headers,
        body: jsonEncode({'message': message}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengirim pesan grup: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadGroupMedia(String groupId, String filePath, String mediaType, {String caption = ''}) async {
    try {
      final headers = await getAuthHeaders();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chat/groups/$groupId/upload-media'));
      request.headers.addAll(headers);
      
      request.fields['mediaType'] = mediaType;
      if (caption.isNotEmpty) {
        request.fields['caption'] = caption;
      }
      
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Gagal mengirim media grup'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // --- CALLS API ---
  
  static Future<Map<String, dynamic>> getCallHistory() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/calls/history'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengambil riwayat panggilan'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
  
  static Future<Map<String, dynamic>> getCallsSocketToken() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/calls/socket-token'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengambil token'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getLiveKitToken(String callId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/calls/$callId/token'),
        headers: headers,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Gagal mengambil LiveKit token'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> startCall(String phone, {String callType = 'audio', String? groupId}) async {
    try {
      final headers = await getAuthHeaders();
      final body = <String, dynamic>{'callType': callType};
      if (groupId != null && groupId.isNotEmpty) {
        body['groupId'] = groupId;
      } else {
        body['phone'] = phone;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/calls/start'),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final err = jsonDecode(response.body);
        return {'success': false, 'message': err['message'] ?? 'Gagal memulai panggilan'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> inviteToCall(String callId, String phone) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/calls/$callId/invite'),
        headers: headers,
        body: jsonEncode({'phone': phone}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final err = jsonDecode(response.body);
        return {'success': false, 'message': err['message'] ?? 'Gagal mengundang kontak'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

    static Future<Map<String, dynamic>> getActiveCall(String callId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/calls/active?callId=$callId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
      final err = jsonDecode(response.body);
      return {'success': false, 'message': err['message'] ?? 'Gagal mengambil active call'};
    }
  } catch (e) {
    return {'success': false, 'message': 'Connection error: $e'};
  }
}

static Future<Map<String, dynamic>> getCallToken(String callId) async {
  try {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/calls/$callId/token'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': jsonDecode(response.body)};
    } else {
      final err = jsonDecode(response.body);
      return {'success': false, 'message': err['message'] ?? 'Gagal mendapatkan token'};
    }
  } catch (e) {
    return {'success': false, 'message': 'Connection error: $e'};
  }
}

  static Future<Map<String, dynamic>> acceptCall(String callId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/calls/$callId/accept'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final err = jsonDecode(response.body);
        return {'success': false, 'message': err['message'] ?? 'Gagal menerima panggilan'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> endCall(String callId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/calls/$callId/end'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal mengakhiri panggilan'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> saveFcmToken(String token) async {
    try {
      final headers = await getAuthHeaders();
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId == null) {
        return {'success': false, 'message': 'User ID not found'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/users/fcm-token'),
        headers: headers,
        body: jsonEncode({
          'userId': userId,
          'token': token
        }),
      );
      
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {'success': false, 'message': 'Gagal menyimpan FCM token'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // --- STORIES ---
  static Future<Map<String, String>> _getPrivacyFields() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString('story_privacy_type') ?? 'kontak_saya';
    final allContacts = await DatabaseHelper().getContacts();
    
    List<String> allowed = [];

    if (type == 'kontak_saya') {
      for (var c in allContacts) {
        if (c['username'] != null) allowed.add(c['username'].toString());
        if (c['phone'] != null) allowed.add(c['phone'].toString());
      }
    } else if (type == 'kecuali') {
      final exceptions = prefs.getStringList('story_privacy_exceptions') ?? [];
      for (var c in allContacts) {
        final u = c['username']?.toString();
        final p = c['phone']?.toString();
        if ((u != null && !exceptions.contains(u)) || (p != null && !exceptions.contains(p))) {
          if (u != null) allowed.add(u);
          if (p != null) allowed.add(p);
        }
      }
    } else if (type == 'hanya_bagikan') {
      allowed = prefs.getStringList('story_privacy_included') ?? [];
    } else if (type == 'teman_dekat') {
      allowed = prefs.getStringList('story_privacy_close_friends') ?? [];
    }

    allowed = allowed.toSet().toList();

    return {
      'privacyType': type,
      'allowedViewers': jsonEncode(allowed),
    };
  }

  static Future<Map<String, dynamic>> deleteStory(String storyId) async { try { final headers = await getAuthHeaders(); final response = await http.delete(Uri.parse('$baseUrl/media/stories/$storyId'), headers: headers); if (response.statusCode == 200 || response.statusCode == 201) return {'success': true}; return {'success': false, 'message': 'Gagal hapus story'}; } catch (e) { return {'success': false, 'message': 'Terjadi kesalahan sistem'}; } }
  static Future<Map<String, dynamic>> deleteMediaPost(String postId) async { try { final headers = await getAuthHeaders(); final response = await http.delete(Uri.parse('$baseUrl/media/posts/$postId'), headers: headers); if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body); return {'success': false, 'message': 'Gagal menghapus postingan'}; } catch (e) { return {'success': false, 'message': 'Terjadi kesalahan sistem'}; } }

    static Future<Map<String, dynamic>> uploadProfilePicture(String profilePicPath) async {
    try {
      final headers = await getAuthHeaders();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/users/profile/picture'));
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath('file', profilePicPath));
      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      return jsonDecode(respStr);
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan saat upload foto'};
    }
  }

    static Future<Map<String, dynamic>> deleteProfilePicture() async {
    try {
      final headers = await getAuthHeaders();
      var response = await http.delete(Uri.parse('/v1/users/profile/picture'), headers: headers);
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan sistem'};
    }
  }

  static Future<Map<String, dynamic>> updateProfile(String name, String about, [String? profilePicPath]) async { try { final headers = await getAuthHeaders(); var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/user/profile')); headers.remove('Content-Type'); request.headers.addAll(headers); request.fields['name'] = name; request.fields['about'] = about; if (profilePicPath != null && profilePicPath.isNotEmpty) { request.files.add(await http.MultipartFile.fromPath('profile_pic', profilePicPath)); } final response = await request.send(); final respStr = await response.stream.bytesToString(); return jsonDecode(respStr); } catch (e) { return {'success': false, 'message': 'Terjadi kesalahan sistem'}; } }
  static Future<Map<String, dynamic>> getStories() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/stories'), headers: headers);
      if (response.statusCode == 200) return {'success': true, 'data': jsonDecode(response.body)['data'] ?? jsonDecode(response.body)};
      return {'success': false, 'message': 'Gagal mengambil stories'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getMyStories() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/stories/my'), headers: headers);
      if (response.statusCode == 200) return {'success': true, 'data': jsonDecode(response.body)['data'] ?? jsonDecode(response.body)};
      return {'success': false, 'message': 'Gagal mengambil stories saya'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> viewStory(String storyId, Map<String, dynamic> viewerData) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/v1/stories/$storyId/viewers'), 
        headers: headers,
        body: jsonEncode(viewerData)
      );
      if (response.statusCode == 200) return {'success': true, 'data': jsonDecode(response.body)};
      return {'success': false, 'message': 'Gagal view story'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getStoryViewers(String storyId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/stories/$storyId/viewers'), headers: headers);
      if (response.statusCode == 200) return {'success': true, 'data': jsonDecode(response.body)['data'] ?? jsonDecode(response.body)};
      return {'success': false, 'message': 'Gagal mengambil viewers'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadTextStory(String text, String bgColor) async {
    try {
      final headers = await getAuthHeaders();
      final privacyFields = await _getPrivacyFields();
      
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/media/upload-story'));
      request.headers.addAll(headers);
      request.fields['type'] = 'text';
      request.fields['caption'] = text;
      request.fields['bgColor'] = bgColor;
      request.fields['privacyType'] = privacyFields['privacyType']!;
      request.fields['allowedViewers'] = privacyFields['allowedViewers']!;

      var response = await request.send();
      var responseString = await response.stream.bytesToString();
      return {'success': response.statusCode == 200, 'data': jsonDecode(responseString)};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadMediaStory(String filePath, String caption) async {
    try {
      final headers = await getAuthHeaders();
      final privacyFields = await _getPrivacyFields();

      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/media/upload-story'));
      request.headers.addAll(headers);
      request.fields['caption'] = caption;
      request.fields['privacyType'] = privacyFields['privacyType']!;
      request.fields['allowedViewers'] = privacyFields['allowedViewers']!;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var response = await request.send();
      var responseString = await response.stream.bytesToString();
      return {'success': response.statusCode == 200, 'data': jsonDecode(responseString)};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // POSTS APIS
  static Future<Map<String, dynamic>> getPosts({int limit = 30, int offset = 0}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/posts?limit=$limit&offset=$offset'), headers: headers);
      if (response.statusCode == 200) return {'success': true, 'data': jsonDecode(response.body)['data'] ?? jsonDecode(response.body)};
      return {'success': false, 'message': 'Gagal mengambil posts'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> likePost(int postId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(Uri.parse('$baseUrl/v1/posts/$postId/like'), headers: headers);
      if (response.statusCode == 200) return {'success': true, 'data': jsonDecode(response.body)};
      return {'success': false, 'message': 'Gagal menyukai post'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadPost(String caption, String? filePath) async {
    try {
      final headers = await getAuthHeaders();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/media/upload-post'));
      request.headers.addAll(headers);
      request.fields['caption'] = caption;
      
      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      }

      var response = await request.send();
      var responseString = await response.stream.bytesToString();
      return {'success': response.statusCode == 200, 'data': jsonDecode(responseString)};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getComments(int postId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/posts/$postId/comments'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['comments'] ?? []};
      }
      return {'success': false, 'message': 'Gagal mengambil komentar'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> addComment(int postId, String text) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/v1/posts/$postId/comments'), 
        headers: headers,
        body: jsonEncode({'text': text})
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['comment']};
      }
      return {'success': false, 'message': 'Gagal mengirim komentar'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- PROFILE API ---
  static Future<Map<String, dynamic>> getMyProfile() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/users/profile'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mengambil profil'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final headers = await getAuthHeaders();
      // Assume the backend API endpoint is /v1/users/:id/profile
      final response = await http.get(Uri.parse('$baseUrl/v1/users/$userId/profile'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mengambil profil pengguna'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> toggleFollow(String userId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(Uri.parse('$baseUrl/v1/users/$userId/follow'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal mengubah status ikuti'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getFollows(String userId, String mode) async {
    try {
      final headers = await getAuthHeaders();
      // mode is either 'followers' or 'following'
      final response = await http.get(Uri.parse('$baseUrl/v1/users/$userId/$mode'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mengambil daftar $mode'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // contentType options: 'posts', 'reels', 'reposts_posts', 'reposts_reels', 'likes', 'saved'
  static Future<Map<String, dynamic>> getUserContent(String userId, String contentType) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/users/$userId/content?type=$contentType'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal memuat konten'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> repostPost(int postId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(Uri.parse('$baseUrl/v1/posts/$postId/repost'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal repost'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> savePost(int postId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(Uri.parse('$baseUrl/v1/posts/$postId/save'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal simpan'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getNotifications({int limit = 30, int offset = 0}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/notifications?limit=$limit&offset=$offset'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mengambil notifikasi'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<int> getUnreadNotificationCount() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/notifications/unread-count'), headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> markNotificationsRead() async {
    try {
      final headers = await getAuthHeaders();
      await http.post(Uri.parse('$baseUrl/v1/notifications/mark-read'), headers: headers);
    } catch (e) {
      // Ignore errors for this background task
    }
  }

  static Future<Map<String, dynamic>> getSinglePost(int postId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/posts/$postId'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mengambil postingan'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> searchUsers(String query) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/v1/users/search?q=$query'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mencari user'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- MARKETPLACE API ---
  static Future<Map<String, dynamic>> getPublicProducts() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/marketplace/public/products'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data'] ?? jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal mengambil produk'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getProductDetail(String id) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/marketplace/public/products/$id'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data'] ?? jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal mengambil detail produk'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> updateCartItemQuantity(String cartId, int quantity) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/marketplace/cart'), 
        headers: headers,
        body: jsonEncode({
          'cartId': cartId,
          'quantity': quantity,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan sistem'};
    }
  }

  static Future<Map<String, dynamic>> deleteCartItem(String cartId) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/marketplace/cart?id=$cartId'), 
        headers: headers,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan sistem'};
    }
  }

  static Future<Map<String, dynamic>> getCart() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/marketplace/cart'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal mengambil keranjang'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> addToCart(String productId, int quantity, {Map<String, dynamic>? variants}) async {
    try {
      final headers = await getAuthHeaders();
      final body = <String, dynamic>{'productId': productId, 'quantity': quantity};
      if (variants != null) {
        body['variants'] = variants;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/marketplace/cart'), 
        headers: headers,
        body: jsonEncode(body)
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal menambah ke keranjang'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> updateStoreProduct(String id, String name, String description, double price, String category, int stock, List<String> variants) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/marketplace/store/products/$id'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'description': description,
          'price': price,
          'category': category,
          'stock': stock,
          'variants': variants,
        }),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal memperbarui produk'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- STORE ORDERS API ---
  
  static Future<Map<String, dynamic>> getStoreOrders() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/marketplace/store/orders'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['data']};
      }
      return {'success': false, 'message': 'Gagal mengambil pesanan'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> updateOrderStatus(int orderId, String status, {String? trackingNumber, String? proof}) async {
    try {
      final headers = await getAuthHeaders();
      
      if (proof != null && proof.isNotEmpty && !proof.startsWith('dummy_')) {
        var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/marketplace/store/orders/$orderId'));
        headers.remove('Content-Type');
        request.headers.addAll(headers);
        
        request.fields['status'] = status;
        if (trackingNumber != null) {
          request.fields['tracking_number'] = trackingNumber;
        }
        request.files.add(await http.MultipartFile.fromPath('completion_proof', proof));
        
        var response = await request.send();
        if (response.statusCode == 200) return {'success': true};
        var responseString = await response.stream.bytesToString();
        return {'success': false, 'message': 'Gagal mengubah status: $responseString'};
      } else {
        final body = <String, dynamic>{'status': status};
        if (trackingNumber != null) body['tracking_number'] = trackingNumber;
        
        final response = await http.put(
          Uri.parse('$baseUrl/marketplace/store/orders/$orderId'),
          headers: headers,
          body: jsonEncode(body),
        );
        if (response.statusCode == 200) {
          return {'success': true};
        }
        return {'success': false, 'message': 'Gagal mengubah status'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- MARKETPLACE ORDERS (BUYER) ---
  
  static Future<Map<String, dynamic>> checkout(List<String> cartItemIds, String address, String phone, String notes) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/marketplace/checkout'),
        headers: headers,
        body: jsonEncode({
          'cartItemIds': cartItemIds,
          'address': address,
          'phone': phone,
          'notes': notes,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal melakukan checkout'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getStoreStatus() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/marketplace/status'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Gagal mengambil status toko'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> registerStore(
    String storeName,
    String fullName,
    String nik,
    String ktpPhotoPath,
    String ownerPhotoPath,
  ) async {
    try {
      final headers = await getAuthHeaders();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/marketplace/register'));
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      
      request.fields['storeName'] = storeName;
      request.fields['fullName'] = fullName;
      request.fields['nik'] = nik;
      
      request.files.add(await http.MultipartFile.fromPath('ktpPhoto', ktpPhotoPath));
      request.files.add(await http.MultipartFile.fromPath('ownerPhoto', ownerPhotoPath));

      var response = await request.send();
      var responseString = await response.stream.bytesToString();
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': jsonDecode(responseString)};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getStoreProducts() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/marketplace/products'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)['products']};
      }
      return {'success': false, 'message': 'Gagal mengambil daftar produk'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteStoreProduct(String id) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.delete(Uri.parse('$baseUrl/marketplace/products?id=$id'), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'message': 'Gagal menghapus produk'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<List<String>> getProductCategories() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse('$baseUrl/central-admin/categories'), headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['categories'] != null) {
          return List<String>.from(data['categories'].map((c) => c['name'].toString()));
        }
      }
      return ['Umum', 'Pakaian', 'Elektronik', 'Makanan', 'Lainnya']; // fallback
    } catch (e) {
      return ['Umum', 'Pakaian', 'Elektronik', 'Makanan', 'Lainnya'];
    }
  }

  static Future<Map<String, dynamic>> addProduct(Map<String, dynamic> data, List<String> imagePaths) async {
    try {
      final headers = await getAuthHeaders();
      
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/marketplace/products'));
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      
      data.forEach((key, value) {
        request.fields[key] = value.toString();
      });
      
      for (var path in imagePaths) {
        request.files.add(await http.MultipartFile.fromPath('media', path));
      }

      var response = await request.send();
      var responseString = await response.stream.bytesToString();
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': jsonDecode(responseString)};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> editProduct(String productId, Map<String, dynamic> data, List<String> imagePaths, List<String> existingMedia) async {
    try {
      final headers = await getAuthHeaders();
      
      var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/marketplace/products'));
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      
      request.fields['id'] = productId;
      data.forEach((key, value) {
        request.fields[key] = value.toString();
      });
      
      request.fields['existingMedia'] = jsonEncode(existingMedia);

      for (var path in imagePaths) {
        request.files.add(await http.MultipartFile.fromPath('media', path));
      }

      var response = await request.send();
      var responseString = await response.stream.bytesToString();
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': jsonDecode(responseString)};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
