import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../main.dart';
import '../services/call_manager.dart';
import '../services/database_helper.dart';

class CallOverlay extends StatefulWidget {
  final Widget child;

  const CallOverlay({super.key, required this.child});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  Offset _pipPosition = const Offset(20, 40);
  Map<String, String> _contactMap = {};
  List<Map<String, dynamic>> _contactList = [];
  bool _showParticipantList = false;
  final Set<String> _selectedPhones = {};
  bool _isInviting = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await DatabaseHelper().getContacts();
    final map = <String, String>{};
    for (final c in contacts) {
      final phone = _normalizePhone(c['phone_number'] as String? ?? '');
      if (phone.isNotEmpty) map[phone] = c['saved_name'] as String? ?? phone;
    }
    if (mounted) {
      setState(() {
        _contactMap = map;
        _contactList = contacts;
      });
    }
  }

  String _normalizePhone(String phone) {
    String p = phone.replaceAll(RegExp(r'\s+|-'), '');
    if (p.startsWith('+62')) p = '0${p.substring(3)}';
    if (p.startsWith('62') && p.length > 10) p = '0${p.substring(2)}';
    return p;
  }

  String _nameForPhone(String phone) {
    return _contactMap[_normalizePhone(phone)] ?? phone;
  }

  String _getParticipantName(RemoteParticipant p) {
    try {
      if (p.metadata != null && p.metadata!.isNotEmpty) {
        final meta = jsonDecode(p.metadata!);
        if (meta['phone'] != null) {
          final phone = _normalizePhone(meta['phone'].toString());
          if (_contactMap.containsKey(phone)) {
            return _contactMap[phone]!;
          }
        }
      }
    } catch (_) {}
    
    // Fallback to LiveKit name, or identity
    return p.name ?? p.identity ?? 'User';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CallManager.instance,
      builder: (context, _) {
        final manager = CallManager.instance;
        return Stack(
          children: [
            widget.child,
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
      return _buildFullscreenView(context, manager);
    }
  }

  // =========================================================================
  // PICTURE-IN-PICTURE (PiP) VIEW
  // =========================================================================
  Widget _buildPiPView(CallManager manager) {
    final remoteParticipants = manager.room.remoteParticipants.values.toList();
    final remoteVideoTrack = remoteParticipants.isNotEmpty
        ? remoteParticipants.first.videoTrackPublications
            .where((pub) => pub.track != null)
            .map((pub) => pub.track)
            .firstOrNull
        : null;

    return Positioned(
      left: _pipPosition.dx,
      top: _pipPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() => _pipPosition += details.delta);
        },
        onTap: () => manager.toggleMinimize(),
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
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group, color: Colors.white, size: 40),
                        if (remoteParticipants.isNotEmpty)
                          Text(
                            '${remoteParticipants.length} orang',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                      ],
                    ),
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
                ),
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
  Widget _buildFullscreenView(BuildContext context, CallManager manager) {
    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              _buildMainContent(manager),

              // Back / Minimize button
              Positioned(
                top: 10,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () => manager.toggleMinimize(),
                ),
              ),

              // Bottom controls
              _buildBottomControls(context, manager),

              // Participant list panel
              if (_showParticipantList)
                _buildParticipantListPanel(manager),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(CallManager manager) {
    if (manager.state != CallState.connected) {
      return _buildWaitingView(manager);
    }

    final remoteParticipants = manager.room.remoteParticipants.values.toList();

    // Use grid for all video calls or multiple participants
    if (manager.isVideo || remoteParticipants.length >= 2) {
      return _buildParticipantsGrid(manager, remoteParticipants);
    }

    // Audio-only call (connected but no video) → show connected view
    return _buildConnectedAudioView(manager);
  }

  Widget _buildConnectedAudioView(CallManager manager) {
    final name = manager.currentOtherUserName ?? 'User';
    final remoteCount = manager.room.remoteParticipants.length;
    final minutes = manager.callDuration.inMinutes.toString().padLeft(2, '0');
    final seconds = (manager.callDuration.inSeconds % 60).toString().padLeft(2, '0');

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.blueGrey.shade700,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            remoteCount > 1 ? '$name + ${remoteCount - 1} lainnya' : name,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_in_talk, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                'Tersambung · $minutes:$seconds',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsGrid(CallManager manager, List<RemoteParticipant> remoteParticipants) {
    // include local participant cell
    final allCells = <Widget>[
      _buildParticipantCell(
        null,
        manager.room.localParticipant,
        label: 'Anda',
        isLocal: true,
      ),
      ...remoteParticipants.map((p) => _buildParticipantCell(
            p,
            null,
            label: _getParticipantName(p),
            isLocal: false,
          )),
    ];

    final count = allCells.length;
    
    if (count <= 2) {
      return Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 160, top: 60),
          child: Column(
            children: allCells.map((cell) => Expanded(child: cell)).toList(),
          ),
        ),
      );
    }

    int crossAxisCount = count <= 4 ? 2 : 3;

    return Positioned.fill(
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        padding: const EdgeInsets.only(bottom: 160, top: 60),
        childAspectRatio: 0.75, // Better ratio for mobile screens
        children: allCells,
      ),
    );
  }

  Widget _buildParticipantCell(
    RemoteParticipant? remote,
    LocalParticipant? local, {
    required String label,
    required bool isLocal,
  }) {
    VideoTrack? videoTrack;
    if (isLocal) {
      videoTrack = local?.videoTrackPublications
          .where((pub) => pub.track != null && !pub.muted)
          .map((pub) => pub.track as VideoTrack)
          .firstOrNull;
    } else {
      videoTrack = remote?.videoTrackPublications
          .where((pub) => pub.track != null && !pub.muted)
          .map((pub) => pub.track as VideoTrack)
          .firstOrNull;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            VideoTrackRenderer(videoTrack)
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blueGrey,
                  child: Icon(Icons.person, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingView(CallManager manager) {
    final name = manager.currentOtherUserName ?? 'User';
    String statusText;
    switch (manager.state) {
      case CallState.calling:
        statusText = manager.isIncoming ? 'Menghubungkan...' : 'Memanggil $name...';
        break;
      case CallState.ringing:
        statusText = 'Panggilan dari $name';
        break;
      case CallState.connected:
        statusText = 'Menghubungkan...';
        break;
      default:
        statusText = '';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blueGrey,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            statusText,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          if (manager.currentGroupId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.tealAccent.shade400, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.groups_rounded, size: 14, color: Colors.tealAccent),
                  SizedBox(width: 4),
                  Text('Panggilan Grup', style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
          if (manager.state == CallState.connected) ...[
            const SizedBox(height: 10),
            Text(
              _formatDuration(manager.callDuration),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildLocalVideo() {
    final localVideoTrack = CallManager.instance.room.localParticipant?.videoTrackPublications
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

  // =========================================================================
  // BOTTOM CONTROLS
  // =========================================================================
  Widget _buildBottomControls(BuildContext context, CallManager manager) {
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: manager.state == CallState.ringing
          ? _buildIncomingControls(manager)
          : _buildActiveCallControls(context, manager),
    );
  }

  Widget _buildIncomingControls(CallManager manager) {
    return Row(
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
    );
  }

  Widget _buildActiveCallControls(BuildContext context, CallManager manager) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Duration display when connected
        if (manager.state == CallState.connected && manager.room.remoteParticipants.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _formatDuration(manager.callDuration),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Mic toggle
            _controlButton(
              heroTag: 'mic',
              icon: manager.isMicMuted ? Icons.mic_off : Icons.mic,
              label: manager.isMicMuted ? 'Mic Off' : 'Mic',
              color: manager.isMicMuted ? Colors.red : Colors.grey.shade800,
              onPressed: () => manager.toggleMic(),
            ),

            // Add participant button
            _controlButton(
              heroTag: 'add_participant',
              icon: Icons.person_add,
              label: 'Tambah',
              color: Colors.blueGrey.shade700,
              onPressed: () async {
                // Refresh contacts every time button is pressed
                final contacts = await DatabaseHelper().getContacts();
                if (mounted) {
                  setState(() {
                    _contactList = contacts;
                    _showParticipantList = true;
                  });
                }
              },
            ),

            // End call
            _controlButton(
              heroTag: 'end',
              icon: Icons.call_end,
              label: 'Tutup',
              color: Colors.red,
              onPressed: () => manager.endCall(),
              size: 64,
            ),

            // Speaker (future: can be toggled)
            _controlButton(
              heroTag: 'speaker',
              icon: Icons.volume_up,
              label: 'Speaker',
              color: Colors.grey.shade800,
              onPressed: () {},
            ),

            // Video toggle (if video call)
            if (manager.isVideo)
              _controlButton(
                heroTag: 'video',
                icon: manager.isVideoMuted ? Icons.videocam_off : Icons.videocam,
                label: manager.isVideoMuted ? 'Kamera Off' : 'Kamera',
                color: manager.isVideoMuted ? Colors.red : Colors.grey.shade800,
                onPressed: () => manager.toggleVideo(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _controlButton({
    required String heroTag,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    double size = 52,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: FloatingActionButton(
            heroTag: heroTag,
            backgroundColor: color,
            mini: size < 56,
            onPressed: onPressed,
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }  Widget _buildParticipantListPanel(CallManager manager) {
    final alreadyInCall = <String>{};
    
    // Add current user and the primary callee
    if (manager.room.localParticipant?.identity != null) {
      alreadyInCall.add(_normalizePhone(manager.room.localParticipant!.identity!));
    }
    if (manager.currentOtherUserPhone != null) {
      alreadyInCall.add(_normalizePhone(manager.currentOtherUserPhone!));
    }
    
    for (final p in manager.room.remoteParticipants.values) {
      alreadyInCall.add(_normalizePhone(p.identity ?? ''));
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.70,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 2),
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        'Tambah Peserta',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (_selectedPhones.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_selectedPhones.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () {
                    setState(() {
                      _showParticipantList = false;
                      _selectedPhones.clear();
                    });
                  },
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 1),
            if (_contactList.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('Tidak ada kontak tersimpan', style: TextStyle(color: Colors.white54)),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _contactList.length,
                  itemBuilder: (_, i) {
                    final c = _contactList[i];
                    final phone = c['phone_number'] as String? ?? '';
                    final name = c['saved_name'] as String? ?? phone;
                    final normalizedPhone = _normalizePhone(phone);
                    final isAlreadyIn = alreadyInCall.contains(normalizedPhone);
                    final isSelected = _selectedPhones.contains(normalizedPhone);

                    return ListTile(
                      onTap: isAlreadyIn
                          ? null
                          : () {
                              setState(() {
                                if (isSelected) {
                                  _selectedPhones.remove(normalizedPhone);
                                } else {
                                  _selectedPhones.add(normalizedPhone);
                                }
                              });
                            },
                      leading: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            backgroundColor: isSelected ? Colors.blueAccent : Colors.blueGrey.shade700,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (isSelected)
                            const CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.blueAccent,
                              child: Icon(Icons.check, size: 12, color: Colors.white),
                            ),
                        ],
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? Colors.blueAccent : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(phone, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      trailing: isAlreadyIn
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade900,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.greenAccent.shade400),
                              ),
                              child: const Text(
                                'Bergabung',
                                style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: Colors.blueAccent,
                                  checkColor: Colors.white,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedPhones.add(normalizedPhone);
                                      } else {
                                        _selectedPhones.remove(normalizedPhone);
                                      }
                                    });
                                  },
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    final result = await manager.inviteParticipant(phone);
                                    if (navigatorKey.currentContext != null && navigatorKey.currentContext!.mounted) {
                                      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
                                        SnackBar(
                                          content: Text(result['success'] == true
                                              ? '$name sedang dipanggil...'
                                              : result['message'] ?? 'Gagal memanggil $name'),
                                          backgroundColor: result['success'] == true
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text('Panggil', style: TextStyle(fontSize: 12, color: Colors.white)),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            if (_selectedPhones.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isInviting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.group_add_rounded, size: 20),
                    label: Text(
                      _isInviting
                          ? 'Mengundang...'
                          : 'Undang ${_selectedPhones.length} Kontak Sekaligus',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isInviting
                        ? null
                        : () async {
                            setState(() => _isInviting = true);
                            final phonesToInvite = _selectedPhones.toList();
                            final result = await manager.inviteParticipants(phonesToInvite);
                            if (mounted) {
                              setState(() {
                                _isInviting = false;
                                _selectedPhones.clear();
                                _showParticipantList = false;
                              });
                            }
                            if (navigatorKey.currentContext != null && navigatorKey.currentContext!.mounted) {
                              ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
                                SnackBar(
                                  content: Text(result['success'] == true
                                      ? '${phonesToInvite.length} kontak sedang dipanggil...'
                                      : result['message'] ?? 'Gagal mengundang kontak'),
                                  backgroundColor: result['success'] == true
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              );
                            }
                          },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
