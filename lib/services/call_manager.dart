import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'database_helper.dart';
import '../main.dart'; // To access navigatorKey

enum CallState { idle, calling, ringing, connected }

class CallManager extends ChangeNotifier {
  static final CallManager _instance = CallManager._internal();
  static CallManager get instance => _instance;

  CallManager._internal() {
    _room = Room();
    _listener = _room.createListener();
    _listener.on<RoomDisconnectedEvent>((event) {
      if (state == CallState.connected) {
        _endLocalCall();
      }
    });

    _listener.on<ParticipantConnectedEvent>((event) {
      if (state == CallState.connected && _durationTimer == null) {
        _startTimer();
      }
      notifyListeners();
    });

    _listener.on<ParticipantDisconnectedEvent>((event) {
      notifyListeners();
    });

    _listener.on<TrackSubscribedEvent>((event) => notifyListeners());
    _listener.on<TrackUnsubscribedEvent>((event) => notifyListeners());
    _listener.on<TrackMutedEvent>((event) => notifyListeners());
    _listener.on<TrackUnmutedEvent>((event) => notifyListeners());
    _listener.on<LocalTrackPublishedEvent>((event) => notifyListeners());
    _listener.on<LocalTrackUnpublishedEvent>((event) => notifyListeners());

  }

  late final Room _room;
  late final EventsListener<RoomEvent> _listener;
  io.Socket? _socket;

  CallState state = CallState.idle;
  
  bool isMinimized = false;
  bool isVideo = false;
  bool isMicMuted = false;
  bool isVideoMuted = false;

  String? currentCallId;
  String? currentOtherUserName;
  String? currentOtherUserPhone;

  Timer? _durationTimer;
  Duration callDuration = Duration.zero;

  bool get isActive => state != CallState.idle;
  Room get room => _room;

  // Initialize socket for incoming calls (called from main.dart)
  Future<void> initSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id');

    final tokenRes = await ApiService.getCallsSocketToken();
    if (!tokenRes['success']) {
      debugPrint('[CallManager] Failed to get calls socket token');
      return;
    }
    final token = tokenRes['data']['token'];

    _socket?.disconnect();
    _socket?.dispose();

    _socket = io.io(ApiService.callsSocketUrl, <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      'auth': {'token': token},
      'path': '/calls-socket/',
    });

    _socket?.onConnect((_) {
      debugPrint('[CallManager] Connected to Calls Signaling Socket');
    });

    _socket?.onConnectError((err) {
      debugPrint('[CallManager] Socket Connect Error: $err');
    });

    _socket?.onError((err) {
      debugPrint('[CallManager] Socket Error: $err');
    });

    _socket?.on('call:incoming', (data) {
      final callData = data['call'];
      final callerName = callData['caller_name'] ?? callData['callerName'] ?? 'Unknown Caller';
      final callerPhone = callData['caller_phone'] ?? callData['callerPhone'] ?? 'Unknown Number';
      final callId = callData['id'].toString();
      final isVideoCall = callData['type'] == 'video';

      final acceptedBy = (callData['accepted_by'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final rejectedBy = (callData['rejected_by'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

      final hasAccepted = currentUserId != null && acceptedBy.contains(currentUserId);
      final hasRejected = currentUserId != null && rejectedBy.contains(currentUserId);

      if (hasAccepted) {
        if (state == CallState.ringing || state == CallState.calling) {
          _fetchLiveKitTokenAndConnect();
        }
      } else if (!hasRejected) {
        handleIncomingCall(callId, callerName, callerPhone, isVideoCall);
      }
    });

    _socket?.on('call:accepted', (data) {
      if (state == CallState.calling) {
        _fetchLiveKitTokenAndConnect();
      }
    });

    _socket?.on('call:declined', (_) {
      _endLocalCall();
    });

    _socket?.on('call:ended', (_) {
      _endLocalCall();
    });

    _socket?.connect();
  }


  Future<void> handleIncomingCall(String callId, String callerName, String callerPhone, bool video) async {
    if (isActive) return;
    currentCallId = callId;
    currentOtherUserName = callerName;
    currentOtherUserPhone = callerPhone;
    isVideo = video;
    isVideoMuted = !video;
    isMicMuted = false;
    isMinimized = false;
    state = CallState.ringing;
    notifyListeners();

    // UI ditangani oleh CallOverlay, tidak perlu show CallKit UI

    // Save to local database
    await DatabaseHelper().insertCallHistory(
      otherPhone: callerPhone,
      otherName: callerName,
      direction: 'incoming',
      status: 'ringing',
      timestamp: DateTime.now().toIso8601String(),
      type: video ? 'video' : 'audio',
    );
  }

  // ---------------------------------------------------------
  // PENELPON (CALLER)
  // ---------------------------------------------------------
  Future<void> startCall(String phone, String otherName, bool video, {String? groupId}) async {
    if (isActive) return;
    
    await Permission.microphone.request();
    if (video) {
      await Permission.camera.request();
    }

    currentOtherUserPhone = phone;
    currentOtherUserName = otherName;
    isVideo = video;
    isVideoMuted = !video;
    isMicMuted = false;
    isMinimized = false;
    state = CallState.calling;
    notifyListeners();

    try {
      final callResult = await ApiService.startCall(phone, callType: video ? 'video' : 'audio', groupId: groupId);
      if (!callResult['success']) throw Exception(callResult['message']);
      
      currentCallId = callResult['data']['call']['id'].toString();
      
      // Save outgoing call to local history
      await DatabaseHelper().insertCallHistory(
        otherPhone: phone,
        otherName: otherName,
        direction: 'outgoing',
        status: 'calling',
        timestamp: DateTime.now().toIso8601String(),
        type: video ? 'video' : 'audio',
      );
      
      notifyListeners();
    } catch (e) {
      debugPrint("Gagal startCall: $e");
      if (navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(content: Text('Error startCall: $e')),
        );
      }
      _endLocalCall();
    }
  }

  // ---------------------------------------------------------
  // PENERIMA (CALLEE)
  // ---------------------------------------------------------
  Future<void> acceptCall() async {
    if (state != CallState.ringing || currentCallId == null) return;
    
    await Permission.microphone.request();
    if (isVideo) {
      await Permission.camera.request();
    }

    state = CallState.calling; // Transisi
    notifyListeners();

    try {
      final res = await ApiService.acceptCall(currentCallId!);
      if (!res['success']) throw Exception(res['message']);

      await _fetchLiveKitTokenAndConnect();
    } catch (e) {
      debugPrint("Gagal acceptCall: $e");
      if (navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(content: Text('Error acceptCall: $e')),
        );
      }
      _endLocalCall();
    }
  }

  Future<void> rejectCall() async {
    if (state != CallState.ringing || currentCallId == null) return;
    await ApiService.endCall(currentCallId!);
    _endLocalCall();
  }

  Future<void> _fetchLiveKitTokenAndConnect() async {
    try {
      final res = await ApiService.getLiveKitToken(currentCallId!);
      if (!res['success']) throw Exception(res['message']);
      
      final String liveKitToken = res['data']['token'];
      final String liveKitUrl = res['data']['url'] ?? 'wss://oc-ch6qludh.livekit.cloud';
      
      await _room.connect(liveKitUrl, liveKitToken);

      if (isVideo) {
        await _room.localParticipant?.setCameraEnabled(true);
      }
      await _room.localParticipant?.setMicrophoneEnabled(true);

      state = CallState.connected;
      if (_room.remoteParticipants.isNotEmpty) {
        _startTimer();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Gagal connect LiveKit: $e");
      if (navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(content: Text('Error LiveKit: $e')),
        );
      }
      _endLocalCall();
    }
  }

  void toggleMinimize() {
    isMinimized = !isMinimized;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    final enabled = _room.localParticipant?.isMicrophoneEnabled() ?? false;
    await _room.localParticipant?.setMicrophoneEnabled(!enabled);
    isMicMuted = enabled;
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    final enabled = _room.localParticipant?.isCameraEnabled() ?? false;
    await _room.localParticipant?.setCameraEnabled(!enabled);
    isVideoMuted = enabled;
    notifyListeners();
  }

  Future<Map<String, dynamic>> inviteParticipant(String phone) async {
    if (currentCallId == null) {
      return {'success': false, 'message': 'Tidak ada panggilan aktif'};
    }
    return await ApiService.inviteToCall(currentCallId!, phone);
  }

  Future<void> endCall() async {
    if (currentCallId != null) {
      await ApiService.endCall(currentCallId!);
    }
    _endLocalCall();
  }

  void _startTimer() {
    callDuration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      callDuration = Duration(seconds: timer.tick);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    callDuration = Duration.zero;
  }

  void _endLocalCall() {
    _stopTimer();
    state = CallState.idle;
    isMinimized = false;
    currentCallId = null;
    currentOtherUserName = null;
    currentOtherUserPhone = null;
    
    _room.disconnect();
    FlutterCallkitIncoming.endAllCalls();
    notifyListeners();
  }

  void logout() {
    _endLocalCall();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
