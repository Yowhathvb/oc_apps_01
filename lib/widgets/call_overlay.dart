import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/call_manager.dart';

class CallOverlay extends StatefulWidget {
  final Widget child;

  const CallOverlay({super.key, required this.child});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  Offset _pipPosition = const Offset(20, 40);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CallManager.instance,
      builder: (context, _) {
        final manager = CallManager.instance;
        return Stack(
          children: [
            // Konten aplikasi utama
            widget.child,

            // Overlay Panggilan
            if (manager.isActive)
              _buildCallUI(context, manager),
          ],
        );
      },
    );
  }

  Widget _buildCallUI(BuildContext context, CallManager manager) {
    if (manager.isMinimized) {
      return _buildPiPView(manager);
    } else {
      return _buildFullscreenView(manager);
    }
  }

  // =========================================================================
  // PICTURE-IN-PICTURE (PiP) VIEW
  // =========================================================================
  Widget _buildPiPView(CallManager manager) {
    final remoteParticipant = manager.room.remoteParticipants.values.isNotEmpty 
        ? manager.room.remoteParticipants.values.first 
        : null;

    final remoteVideoTrack = remoteParticipant?.videoTrackPublications
        .where((pub) => pub.track != null)
        .map((pub) => pub.track)
        .firstOrNull;

    return Positioned(
      left: _pipPosition.dx,
      top: _pipPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipPosition += details.delta;
          });
        },
        onTap: () {
          manager.toggleMinimize();
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 120,
            height: 160,
            color: Colors.black87,
            child: Stack(
              children: [
                if (manager.state == CallState.connected && remoteVideoTrack != null)
                  Positioned.fill(
                    child: VideoTrackRenderer(remoteVideoTrack as VideoTrack),
                  )
                else
                  const Center(
                    child: Icon(Icons.person, color: Colors.white, size: 50),
                  ),
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(manager.isMicMuted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 20),
                      if (manager.isVideo)
                        Icon(manager.isVideoMuted ? Icons.videocam_off : Icons.videocam, color: Colors.white, size: 20),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // FULLSCREEN VIEW
  // =========================================================================
  Widget _buildFullscreenView(CallManager manager) {
    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              // Latar Belakang / Video Jarak Jauh
              _buildFullscreenBackground(manager),

              // Tombol Minimize
              Positioned(
                top: 10,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () {
                    manager.toggleMinimize();
                  },
                ),
              ),

              // Video Lokal (Kecil)
              if (manager.state == CallState.connected && manager.isVideo && !manager.isVideoMuted)
                _buildLocalVideo(manager),

              // Panel Kontrol / Tombol Terima/Tolak
              _buildBottomControls(manager),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenBackground(CallManager manager) {
    if (manager.state == CallState.connected) {
      final remoteParticipant = manager.room.remoteParticipants.values.isNotEmpty 
          ? manager.room.remoteParticipants.values.first 
          : null;
      final remoteVideoTrack = remoteParticipant?.videoTrackPublications
          .where((pub) => pub.track != null)
          .map((pub) => pub.track)
          .firstOrNull;

      if (remoteVideoTrack != null) {
        return Positioned.fill(
          child: VideoTrackRenderer(remoteVideoTrack as VideoTrack),
        );
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            _getStatusText(manager),
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  String _getStatusText(CallManager manager) {
    final name = manager.currentOtherUserName ?? 'User';
    switch (manager.state) {
      case CallState.calling:
        return 'Memanggil $name...';
      case CallState.ringing:
        return 'Panggilan dari $name';
      case CallState.connected:
        if (manager.room.remoteParticipants.isEmpty) {
          return 'Menghubungkan...';
        }
        final minutes = manager.callDuration.inMinutes.toString().padLeft(2, '0');
        final seconds = (manager.callDuration.inSeconds % 60).toString().padLeft(2, '0');
        return '$minutes:$seconds\nTersambung';
      default:
        return '';
    }
  }

  Widget _buildLocalVideo(CallManager manager) {
    final localVideoTrack = manager.room.localParticipant?.videoTrackPublications
        .where((pub) => pub.track != null)
        .map((pub) => pub.track)
        .firstOrNull;

    if (localVideoTrack == null) return const SizedBox.shrink();

    return Positioned(
      top: 60,
      right: 20,
      child: Container(
        width: 100,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: VideoTrackRenderer(localVideoTrack as VideoTrack),
      ),
    );
  }

  Widget _buildBottomControls(CallManager manager) {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: manager.state == CallState.ringing
          // Kontrol Incoming Call
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'reject',
                      backgroundColor: Colors.red,
                      onPressed: () => manager.rejectCall(),
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text('Tolak', style: TextStyle(color: Colors.white)),
                  ],
                ),
                Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'accept',
                      backgroundColor: Colors.green,
                      onPressed: () => manager.acceptCall(),
                      child: const Icon(Icons.call, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text('Terima', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ],
            )
          // Kontrol Panggilan Aktif
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'mic',
                  backgroundColor: manager.isMicMuted ? Colors.red : Colors.grey.shade800,
                  onPressed: () => manager.toggleMic(),
                  child: Icon(manager.isMicMuted ? Icons.mic_off : Icons.mic, color: Colors.white),
                ),
                FloatingActionButton(
                  heroTag: 'end',
                  backgroundColor: Colors.red,
                  onPressed: () => manager.endCall(),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 30),
                ),
                if (manager.isVideo)
                  FloatingActionButton(
                    heroTag: 'video',
                    backgroundColor: manager.isVideoMuted ? Colors.red : Colors.grey.shade800,
                    onPressed: () => manager.toggleVideo(),
                    child: Icon(manager.isVideoMuted ? Icons.videocam_off : Icons.videocam, color: Colors.white),
                  ),
              ],
            ),
    );
  }
}
