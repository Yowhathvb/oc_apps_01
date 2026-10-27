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

  CallManager._internal();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  io.Socket? _socket;

  Room get room => _room ??= _createRoom();

  Room _createRoom() {
    _room?.disconnect();
    _room?.dispose();
    _listener?.dispose();

    final r = Room(
      roomOptions: const RoomOptions(
        defaultAudioPublishOptions: AudioPublishOptions(
          dtx: true,
        ),
      ),
    );
    _listener = r.createListener();
    _listener!.on<RoomDisconnectedEvent>((event) {
      if (state == CallState.connected) {
        _endLocalCall();
      }
    });

    _listener!.on<ParticipantConnectedEvent>((event) {
      if (state == CallState.connected && _durationTimer == null) {
        _startTimer();
      }
      notifyListeners();
    });

    _listener!.on<ParticipantDisconnectedEvent>((event) {
      notifyListeners();
    });

    _listener!.on<TrackSubscribedEvent>((event) => notifyListeners());
    _listener!.on<TrackUnsubscribedEvent>((event) => notifyListeners());
    _listener!.on<TrackMutedEvent>((event) => notifyListeners());
    _listener!.on<TrackUnmutedEvent>((event) => notifyListeners());
    _listener!.on<LocalTrackPublishedEvent>((event) => notifyListeners());
    _listener!.on<LocalTrackUnpublishedEvent>((event) => notifyListeners());

    _room = r;
    return r;
  }

  CallState state = CallState.idle;
  
  bool isIncoming = false;
  bool _isConnecting = false;
  bool isMinimized = false;
  bool isVideo = false;
  bool isMicMuted = false;
  bool isVideoMuted = false;

  String? currentCallId;
  String? currentOtherUserName;
  String? currentOtherUserPhone;
  String? currentGroupId;

  Timer? _durationTimer;
  Duration callDuration = Duration.zero;

  bool get isActive => state != CallState.idle;

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
      'transports': ['websocket'],
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
      final groupId = callData['group_id'] ?? callData['groupId'];

      final acceptedBy = (callData['accepted_by'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final rejectedBy = (callData['rejected_by'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

      final hasAccepted = currentUserId != null && acceptedBy.contains(currentUserId);
      final hasRejected = currentUserId != null && rejectedBy.contains(currentUserId);

      if (hasAccepted) {
        if (state == CallState.ringing || state == CallState.calling) {
          _fetchLiveKitTokenAndConnect();
        }
      } else if (!hasRejected) {
        handleIncomingCall(callId, callerName, callerPhone, isVideoCall, groupId: groupId?.toString());
      }
    });

    _socket?.on('call:accepted', (data) {
      if (!isIncoming && state == CallState.calling) {
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


  Future<void> handleIncomingCall(
    String callId,
    String callerName,
    String callerPhone,
    bool video, {
    String? groupId,
  }) async {
    if (isActive) return;
    isIncoming = true;
    currentCallId = callId;
    currentOtherUserName = callerName;
    currentOtherUserPhone = callerPhone;
    currentGroupId = groupId;
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
  Future<void> startCall(
    String? phone,
    String otherName,
    bool video, {
    String? groupId,
    List<String>? phones,
  }) async {
    if (isActive) return;
    
    await Permission.microphone.request();
    if (video) {
      await Permission.camera.request();
    }

    isIncoming = false;
    currentOtherUserPhone = (phones != null && phones.isNotEmpty)
        ? phones.join(', ')
        : (phone ?? '');
    currentOtherUserName = otherName;
    currentGroupId = groupId;
    isVideo = video;
    isVideoMuted = !video;
    isMicMuted = false;
    isMinimized = false;
    state = CallState.calling;
    notifyListeners();

    try {
      final callResult = await ApiService.startCall(
        phone,
        phones: phones,
        callType: video ? 'video' : 'audio',
        groupId: groupId,
      );
      if (!callResult['success']) throw Exception(callResult['message']);
      
      currentCallId = callResult['data']['call']['id'].toString();
      
      // Save outgoing call to local history
      await DatabaseHelper().insertCallHistory(
        otherPhone: (phones != null && phones.isNotEmpty)
            ? phones.join(', ')
            : (phone ?? (groupId != null ? 'Grup' : '')),
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
    if (_isConnecting || state == CallState.connected) {
      debugPrint('[CallManager] Already connecting or connected to LiveKit, ignoring duplicate call');
      return;
    }
    _isConnecting = true;
    try {
      final res = await ApiService.getLiveKitToken(currentCallId!);
      if (!res['success']) throw Exception(res['message']);
      
      final String liveKitToken = res['data']['token'];
      final String liveKitUrl = res['data']['url'] ?? 'wss://oc-ch6qludh.livekit.cloud';
      debugPrint('[CallManager] Connecting to LiveKit URL: $liveKitUrl');
      
      final currentRoom = _createRoom();
      await currentRoom.connect(
        liveKitUrl,
        liveKitToken,
        connectOptions: const ConnectOptions(
          autoSubscribe: true,
          rtcConfiguration: RTCConfiguration(
            iceServers: [
              RTCIceServer(urls: [
                'stun:stun.l.google.com:19302',
                'stun:stun1.l.google.com:19302',
                'stun:stun2.l.google.com:19302',
              ]),
            ],
          ),
        ),
      );

      if (isVideo) {
        await currentRoom.localParticipant?.setCameraEnabled(true);
      }
      await currentRoom.localParticipant?.setMicrophoneEnabled(true);

      state = CallState.connected;
      if (currentRoom.remoteParticipants.isNotEmpty) {
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
    } finally {
      _isConnecting = false;
    }
  }

  void toggleMinimize() {
    isMinimized = !isMinimized;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    final enabled = _room?.localParticipant?.isMicrophoneEnabled() ?? false;
    await _room?.localParticipant?.setMicrophoneEnabled(!enabled);
    isMicMuted = enabled;
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    final enabled = _room?.localParticipant?.isCameraEnabled() ?? false;
    await _room?.localParticipant?.setCameraEnabled(!enabled);
    isVideoMuted = enabled;
    notifyListeners();
  }

  Future<Map<String, dynamic>> inviteParticipant(String phone) async {
    if (currentCallId == null) {
      return {'success': false, 'message': 'Tidak ada panggilan aktif'};
    }
    return await ApiService.inviteToCall(currentCallId!, phone);
  }

  Future<Map<String, dynamic>> inviteParticipants(List<String> phones) async {
    if (currentCallId == null) {
      return {'success': false, 'message': 'Tidak ada panggilan aktif'};
    }
    return await ApiService.inviteToCall(currentCallId!, phones);
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
    isIncoming = false;
    _isConnecting = false;
    isMinimized = false;
    currentCallId = null;
    currentOtherUserName = null;
    currentOtherUserPhone = null;
    currentGroupId = null;
    
    _room?.disconnect();
    _room?.dispose();
    _room = null;
    _listener?.dispose();
    _listener = null;

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
