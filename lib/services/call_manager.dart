import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'database_helper.dart';

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

    _listenToCallKitEvents();
  }

  late final Room _room;
  late final EventsListener<RoomEvent> _listener;
  IO.Socket? _socket;

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
    final tokenRes = await ApiService.getCallsSocketToken();
    if (!tokenRes['success']) {
      debugPrint('[CallManager] Failed to get calls socket token');
      return;
    }
    final token = tokenRes['data']['token'];

    _socket?.disconnect();
    _socket?.dispose();

    _socket = IO.io(ApiService.callsSocketUrl, <String, dynamic>{
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
      final callerName = callData['caller_name'] ?? 'Unknown Caller';
      final callerPhone = callData['caller_phone'] ?? 'Unknown Number';
      final callId = callData['id'].toString();
      final isVideoCall = callData['type'] == 'video';

      handleIncomingCall(callId, callerName, callerPhone, isVideoCall);
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

  void _listenToCallKitEvents() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      
      if (event is CallEventActionCallAccept) {
        await acceptCall();
      } else if (event is CallEventActionCallDecline) {
        await rejectCall();
      }
    });
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

    CallKitParams callKitParams = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Our Chat',
      avatar: 'https://i.pravatar.cc/100', // Example avatar
      handle: callerPhone,
      type: video ? 1 : 0,
      duration: 30000,
      extra: <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F3460',
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);

    // Save to local database
    await DatabaseHelper().insertCallHistory(
      otherPhone: callerPhone,
      otherName: callerName,
      direction: 'incoming',
      status: 'ringing',
      timestamp: DateTime.now().toIso8601String(),
    );
  }

  // ---------------------------------------------------------
  // PENELPON (CALLER)
  // ---------------------------------------------------------
  Future<void> startCall(String phone, String otherName, bool video) async {
    if (isActive) return;
    
    currentOtherUserPhone = phone;
    currentOtherUserName = otherName;
    isVideo = video;
    isVideoMuted = !video;
    isMicMuted = false;
    isMinimized = false;
    state = CallState.calling;
    notifyListeners();

    try {
      final callResult = await ApiService.startCall(phone);
      if (!callResult['success']) throw Exception(callResult['message']);
      
      currentCallId = callResult['data']['call']['id'].toString();
      notifyListeners();
    } catch (e) {
      debugPrint("Gagal startCall: $e");
      _endLocalCall();
    }
  }

  // ---------------------------------------------------------
  // PENERIMA (CALLEE)
  // ---------------------------------------------------------
  Future<void> acceptCall() async {
    if (state != CallState.ringing || currentCallId == null) return;
    
    state = CallState.calling; // Transisi
    notifyListeners();

    try {
      final res = await ApiService.acceptCall(currentCallId!);
      if (!res['success']) throw Exception(res['message']);

      await _fetchLiveKitTokenAndConnect();
    } catch (e) {
      debugPrint("Gagal acceptCall: $e");
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
