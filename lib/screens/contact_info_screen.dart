import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../services/call_manager.dart';
import 'chat_screen.dart';

class ContactInfoScreen extends StatefulWidget {
  final String phone;
  final String? displayName;
  final String? profilePic;
  final String? roomId;
  final bool isGroup;

  const ContactInfoScreen({
    super.key,
    required this.phone,
    this.displayName,
    this.profilePic,
    this.roomId,
    this.isGroup = false,
  });

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  static const Color _primaryColor = Color(0xFF0F3460);
  static const Color _dividerColor = Color(0xFFEDF0F5);
  static const Color _subtleBg = Color(0xFFF7F9FC);

  bool _isLoading = true;
  String _displayName = '';
  String? _originalName;
  String? _username;
  String _about = '';
  String? _profilePic;
  String? _resolvedRoomId;
  bool _isSavedLocally = false;

  List<Map<String, dynamic>> _mediaList = [];
  bool _isLoadingMedia = false;

  // Group members & admin state
  List<Map<String, dynamic>> _groupMembers = [];
  bool _isLoadingMembers = false;
  String? _myUserId;
  Map<String, dynamic>? _groupData;
  bool _isCurrentUserAdmin = false;
  bool _isCurrentUserCreator = false;
  bool get _canEditGroupInfo =>
      widget.isGroup &&
      (_isCurrentUserAdmin || (_groupData?['edit_info_permission'] ?? 'admins_only') == 'all');

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName ?? (widget.isGroup ? 'Grup' : widget.phone);
    _profilePic = widget.profilePic;
    _resolvedRoomId = widget.roomId;
    _loadData();
  }

  String _normalizePhone(String? p) {
    if (p == null) return '';
    String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (num.startsWith('62')) {
      return '0${num.substring(2)}';
    }
    return num;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getString('user_id');

    // 1. Ambil Kontak dari SQLite Lokal
    final contacts = await DatabaseHelper().getContacts();
    final Map<String, String> localContactsMap = {};
    for (var c in contacts) {
      final p = _normalizePhone(c['phone_number']?.toString());
      if (p.isNotEmpty) {
        localContactsMap[p] = c['saved_name']?.toString() ?? '';
      }
    }

    // Jika ini adalah grup
    if (widget.isGroup) {
      _displayName = widget.displayName ?? 'Grup';
      _resolvedRoomId = widget.roomId;
      _about = 'Grup Our Chat';
      if (_resolvedRoomId != null) {
        await _loadGroupDataAndMedia(_resolvedRoomId!, localContactsMap);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    // 2. Jika Kontak Pribadi (1-on-1): Cek Nama Lokal
    final targetPhone = _normalizePhone(widget.phone);
    Map<String, dynamic>? localMatch;

    for (var c in contacts) {
      if (_normalizePhone(c['phone_number']?.toString()) == targetPhone) {
        localMatch = c;
        break;
      }
    }

    if (localMatch != null && (localMatch['saved_name'] ?? '').toString().isNotEmpty) {
      _displayName = localMatch['saved_name'];
      _isSavedLocally = true;
    }

    // 3. Ambil Profil Pengguna dari API Server
    try {
      final userRes = await ApiService.findUserByPhone(widget.phone);
      if (userRes['success'] == true && userRes['data'] != null) {
        final u = userRes['data'];
        _originalName = u['name'] ?? u['username'];
        _username = u['username'];
        _about = u['about'] ?? 'Ada di Our Chat';
        if (_profilePic == null || _profilePic!.isEmpty) {
          _profilePic = u['profile_pic'];
        }
        if (!_isSavedLocally) {
          _displayName = _originalName ?? widget.phone;
        }
      }
    } catch (e) {
      debugPrint('[ContactInfo] Gagal fetch user: $e');
    }

    // 4. Cek Room ID lokal di SQLite
    if (_resolvedRoomId == null && !widget.isGroup) {
      _resolvedRoomId = await DatabaseHelper().getLocalRoomId(widget.phone);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }

    // 5. Muat media dari room chat jika roomId tersedia
    if (_resolvedRoomId != null) {
      _loadRoomMedia(_resolvedRoomId!);
    }
  }

  Future<void> _loadGroupDataAndMedia(String groupId, Map<String, String> localContactsMap) async {
    setState(() {
      _isLoadingMedia = true;
      _isLoadingMembers = true;
    });

    final cleanId = groupId.replaceFirst('group_', '');

    try {
      // 1. Ambil detail grup lengkap (roles, admins, permissions, description, dll)
      final detailRes = await ApiService.getGroupDetails(cleanId);
      List rawMembers = [];
      if (detailRes['success'] == true && detailRes['data'] != null) {
        final g = detailRes['data'];
        _groupData = g;
        _displayName = g['name'] ?? _displayName;
        _about = g['description'] ?? '';
        if (g['profile_pic'] != null && g['profile_pic'].toString().isNotEmpty) {
          _profilePic = g['profile_pic'];
        }

        final currentUser = g['current_user'];
        _isCurrentUserAdmin = currentUser?['is_admin'] == true;
        _isCurrentUserCreator = currentUser?['is_creator'] == true;

        rawMembers = g['members'] ?? [];
      }

      // 2. Ambil media grup dari messages
      final msgRes = await ApiService.getGroupMessages(cleanId);
      if (rawMembers.isEmpty && msgRes['success'] == true && msgRes['data'] != null) {
        rawMembers = msgRes['data']['members'] ?? [];
      }

      final List<Map<String, dynamic>> parsedMembers = [];
      for (var m in rawMembers) {
        final rawPhone = m['phone']?.toString() ?? '';
        final normPhone = _normalizePhone(rawPhone);
        final isMe = m['id']?.toString() == _myUserId;
        final localName = localContactsMap[normPhone];

        String memberDisplayName;
        if (isMe) {
          memberDisplayName = 'Anda';
        } else if (localName != null && localName.trim().isNotEmpty) {
          memberDisplayName = localName.trim();
        } else if (m['name'] != null && m['name'].toString().trim().isNotEmpty) {
          memberDisplayName = m['name'].toString().trim();
        } else if (normPhone.isNotEmpty) {
          memberDisplayName = normPhone;
        } else {
          memberDisplayName = 'Anggota Grup';
        }

        final bool isCreator = m['is_creator'] == true || (_groupData != null && m['id'] == _groupData!['created_by']);
        final bool isAdmin = m['is_admin'] == true || m['role'] == 'admin' || isCreator;

        parsedMembers.add({
          'id': m['id'],
          'display_name': memberDisplayName,
          'original_name': m['name'] ?? '',
          'phone': rawPhone,
          'is_me': isMe,
          'is_saved': !isMe && localName != null && localName.trim().isNotEmpty,
          'profile_pic': m['profile_pic'],
          'role': isAdmin ? 'admin' : 'member',
          'is_admin': isAdmin,
          'is_creator': isCreator,
        });
      }

      // Urutan anggota:
      // 1. "Anda" paling atas
      // 2. Pembuat grup (Creator)
      // 3. Admin grup lainnya
      // 4. Anggota biasa (alfabetis)
      parsedMembers.sort((a, b) {
        if (a['is_me'] == true) return -1;
        if (b['is_me'] == true) return 1;
        if (a['is_creator'] == true && b['is_creator'] != true) return -1;
        if (b['is_creator'] == true && a['is_creator'] != true) return 1;
        if (a['is_admin'] == true && b['is_admin'] != true) return -1;
        if (b['is_admin'] == true && a['is_admin'] != true) return 1;
        return (a['display_name'] as String)
            .toLowerCase()
            .compareTo((b['display_name'] as String).toLowerCase());
      });

      // Parse Media
      List<Map<String, dynamic>> media = [];
      if (msgRes['success'] == true && msgRes['data'] != null) {
        final List msgs = msgRes['data']['messages'] ?? [];
        media = msgs.where((m) {
          final type = m['media_type'];
          final url = m['media_url'];
          return url != null &&
              url.toString().isNotEmpty &&
              (type == 'image' || type == 'video' || type == 'file' || type == 'audio');
        }).map((m) => Map<String, dynamic>.from(m)).toList();
      }

      if (mounted) {
        setState(() {
          _groupMembers = parsedMembers;
          _mediaList = media;
          _isLoadingMedia = false;
          _isLoadingMembers = false;
          _isLoading = false;
        });
      }
      return;
    } catch (e) {
      debugPrint('[ContactInfo] Gagal load data grup: $e');
    }

    if (mounted) {
      setState(() {
        _isLoadingMedia = false;
        _isLoadingMembers = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRoomMedia(String roomId) async {
    setState(() => _isLoadingMedia = true);
    try {
      final res = widget.isGroup
          ? await ApiService.getGroupMessages(roomId)
          : await ApiService.getChatMessages(roomId, limit: 100);

      if (res['success'] == true && res['data'] != null) {
        final List msgs = res['data']['messages'] ?? [];
        final media = msgs.where((m) {
          final type = m['media_type'];
          final url = m['media_url'];
          return url != null &&
              url.toString().isNotEmpty &&
              (type == 'image' || type == 'video' || type == 'file' || type == 'audio');
        }).map((m) => Map<String, dynamic>.from(m)).toList();

        if (mounted) {
          setState(() {
            _mediaList = media;
            _isLoadingMedia = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('[ContactInfo] Gagal load media: $e');
    }
    if (mounted) {
      setState(() => _isLoadingMedia = false);
    }
  }

  void _showEditContactDialog() {
    final nameController = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text(
            'Edit Nama Kontak',
            style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.black87),
            decoration: const InputDecoration(
              hintText: 'Masukkan nama lokal',
              hintStyle: TextStyle(color: Colors.grey),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  await DatabaseHelper().saveContact(widget.phone, newName, isRegistered: true);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    setState(() {
                      _displayName = newName;
                      _isSavedLocally = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nama kontak berhasil disimpan')),
                    );
                  }
                }
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _goToChat() async {
    if (_resolvedRoomId != null) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
            roomId: _resolvedRoomId!,
            otherUserName: _displayName,
            otherUserPhone: widget.phone,
            profilePic: _profilePic,
            isGroup: widget.isGroup,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      );
    } else {
      String? localRoomId = await DatabaseHelper().getLocalRoomId(widget.phone);
      if (localRoomId == null || localRoomId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final myUsername = prefs.getString('username') ?? prefs.getString('user_id') ?? 'user';
        localRoomId = DatabaseHelper.generateUniqueRoomId(myUsername);
        await DatabaseHelper().saveContact(
          widget.phone,
          _displayName,
          isRegistered: true,
          localRoomId: localRoomId,
        );
      }
      _resolvedRoomId = localRoomId;
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
              roomId: _resolvedRoomId!,
              otherUserName: _displayName,
              otherUserPhone: widget.phone,
              profilePic: _profilePic,
              isGroup: widget.isGroup,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
              return SlideTransition(
                position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
                child: FadeTransition(opacity: curved, child: child),
              );
            },
          ),
        );
      }
    }
  }

  void _showCallPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.call_rounded, color: Colors.green, size: 28),
                title: Text(
                  widget.isGroup ? 'Panggilan Suara Grup' : 'Panggilan Suara',
                  style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  widget.isGroup ? '${_groupMembers.length} Anggota Grup' : widget.phone,
                  style: const TextStyle(color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  CallManager.instance.startCall(
                    widget.phone,
                    _displayName,
                    false,
                    groupId: widget.isGroup ? _resolvedRoomId : null,
                  );
                },
              ),
              const Divider(color: _dividerColor, height: 1),
              ListTile(
                leading: const Icon(Icons.videocam_rounded, color: Colors.teal, size: 28),
                title: Text(
                  widget.isGroup ? 'Panggilan Video Grup' : 'Panggilan Video',
                  style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  widget.isGroup ? '${_groupMembers.length} Anggota Grup' : widget.phone,
                  style: const TextStyle(color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  CallManager.instance.startCall(
                    widget.phone,
                    _displayName,
                    true,
                    groupId: widget.isGroup ? _resolvedRoomId : null,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openMediaGallery() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) => RoomMediaGalleryScreen(
          chatTitle: _displayName,
          mediaList: _mediaList,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageAndVideos = _mediaList
        .where((m) => m['media_type'] == 'image' || m['media_type'] == 'video')
        .take(3)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          widget.isGroup ? 'Info Grup' : 'Info Kontak',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!widget.isGroup)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                if (val == 'edit') {
                  _showEditContactDialog();
                } else if (val == 'copy') {
                  Clipboard.setData(ClipboardData(text: widget.phone));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nomor telepon disalin ke clipboard')),
                  );
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: _primaryColor, size: 20),
                      SizedBox(width: 10),
                      Text('Edit Nama Kontak', style: TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, color: _primaryColor, size: 20),
                      SizedBox(width: 10),
                      Text('Salin Nomor', style: TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // 1. Profil Header (Menyatu dengan Body, Tanpa Kontainer)
                _buildHeaderSection(),

                const Divider(height: 1, thickness: 1, color: _dividerColor),
                Container(height: 10, color: _subtleBg),
                const Divider(height: 1, thickness: 1, color: _dividerColor),

                // 2. Menu Item: Nomor HP (Hanya untuk kontak personal, disembunyikan untuk grup)
                if (!widget.isGroup) ...[
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.phone));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nomor telepon disalin ke clipboard')),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          const Text(
                            'Nomor HP',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            widget.phone,
                            style: const TextStyle(
                              color: _primaryColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.copy_rounded, color: Colors.grey.shade400, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, color: _dividerColor, indent: 20, endIndent: 20),
                ],

                // 3. Menu Item: Deskripsi
                InkWell(
                  onTap: (widget.isGroup && _canEditGroupInfo) ? _editGroupDescription : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Deskripsi',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            _about.isNotEmpty
                                ? _about
                                : (widget.isGroup ? 'Tambah deskripsi grup...' : 'Ada di Our Chat'),
                            style: TextStyle(
                              color: (_about.isEmpty && widget.isGroup)
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade600,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          (widget.isGroup && _canEditGroupInfo)
                              ? Icons.edit_outlined
                              : Icons.chevron_right_rounded,
                          color: (widget.isGroup && _canEditGroupInfo)
                              ? _primaryColor
                              : Colors.grey.shade400,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: _dividerColor, indent: 20, endIndent: 20),

                // 4. Menu Item: Media
                InkWell(
                  onTap: _openMediaGallery,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Media',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Foto, video & dokumen',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (_isLoadingMedia)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        else if (imageAndVideos.isNotEmpty) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: imageAndVideos.map((m) {
                              final isVideo = m['media_type'] == 'video';
                              final url = ApiService.getServerUrl(m['media_url'] ?? '');
                              return Container(
                                margin: const EdgeInsets.only(left: 6),
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      isVideo
                                          ? Container(
                                              color: Colors.black54,
                                              child: const Icon(Icons.videocam, color: Colors.white70, size: 20),
                                            )
                                          : CachedNetworkImage(
                                              imageUrl: url,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, url, error) =>
                                                  const Icon(Icons.image, color: Colors.black26),
                                            ),
                                      if (isVideo)
                                        const Center(
                                          child: Icon(Icons.play_circle_fill, size: 16, color: Colors.white),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(width: 8),
                        ] else ...[
                          Text(
                            '${_mediaList.length} file',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
                      ],
                    ),
                  ),
                ),

                // 4.5 Khusus Admin Grup: Pengaturan Grup
                if (widget.isGroup && _isCurrentUserAdmin) ...[
                  const Divider(height: 1, thickness: 1, color: _dividerColor, indent: 20, endIndent: 20),
                  InkWell(
                    onTap: _showGroupSettingsModal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: _primaryColor, size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pengaturan Grup',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Izin edit info & kirim pesan',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],

                // 5. Khusus Grup: Daftar Anggota Grup beserta Nomor HP
                if (widget.isGroup) ...[
                  const Divider(height: 1, thickness: 1, color: _dividerColor),
                  Container(height: 12, color: _subtleBg),
                  const Divider(height: 1, thickness: 1, color: _dividerColor),

                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 12, top: 14, bottom: 6),
                    child: Row(
                      children: [
                        Text(
                          '${_groupMembers.length} Anggota',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_isCurrentUserAdmin)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: _primaryColor,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                            label: const Text('Tambah', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: _showAddMembersModal,
                          ),
                      ],
                    ),
                  ),

                  if (_isLoadingMembers)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_groupMembers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text(
                        'Belum ada data anggota grup',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    )
                  else
                    ..._groupMembers.map((member) => _buildMemberTile(member)),
                ],

                const Divider(height: 1, thickness: 1, color: _dividerColor),
                Container(height: 16, color: _subtleBg),
                const Divider(height: 1, thickness: 1, color: _dividerColor),

                // 6. Tombol Aksi Bawah: Kirim Pesan
                InkWell(
                  onTap: _goToChat,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, color: _primaryColor, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Kirim Pesan',
                          style: TextStyle(
                            color: _primaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: _dividerColor),

                // 7. Tombol Aksi Bawah: Panggilan Suara dan Video
                InkWell(
                  onTap: _showCallPicker,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.call_outlined, color: _primaryColor, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Panggilan Suara dan Video',
                          style: TextStyle(
                            color: _primaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 8. Khusus Grup: Keluar dari Grup
                if (widget.isGroup) ...[
                  const Divider(height: 1, thickness: 1, color: _dividerColor),
                  InkWell(
                    onTap: _confirmLeaveGroup,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Keluar dari Grup',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const Divider(height: 1, thickness: 1, color: _dividerColor),
                Container(height: 40, color: _subtleBg),
              ],
            ),
    );
  }
  Future<void> _pickAndUploadGroupPhoto() async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (picked == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mengunggah foto grup...')),
      );

      final res = await ApiService.uploadGroupProfilePic(cleanId, picked.path);
      if (res['success'] == true) {
        setState(() {
          _profilePic = res['profilePic'];
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto grup berhasil diperbarui!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal mengunggah foto grup'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('[GroupPhoto] Error: $e');
    }
  }

  Future<void> _editGroupName() async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty) return;

    final controller = TextEditingController(text: _displayName);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama Grup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            maxLength: 50,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nama Grup',
              hintText: 'Ketik nama grup baru...',
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Nama tidak boleh kosong' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final newName = controller.text.trim();
              Navigator.pop(ctx);

              final res = await ApiService.updateGroupInfo(cleanId, name: newName);
              if (res['success'] == true) {
                setState(() => _displayName = newName);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nama grup berhasil diubah!'), backgroundColor: Colors.green),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res['message'] ?? 'Gagal mengubah nama grup'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGroupDescription() async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty) return;

    final controller = TextEditingController(text: _about);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deskripsi Grup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Tambahkan deskripsi grup...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              final newDesc = controller.text.trim();
              Navigator.pop(ctx);

              final res = await ApiService.updateGroupInfo(cleanId, description: newDesc);
              if (res['success'] == true) {
                setState(() => _about = newDesc);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Deskripsi grup berhasil diubah!'), backgroundColor: Colors.green),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res['message'] ?? 'Gagal mengubah deskripsi grup'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupSettingsModal() async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty) return;

    String editInfoPerm = _groupData?['edit_info_permission'] ?? 'admins_only';
    String sendMessagesPerm = _groupData?['send_messages_permission'] ?? 'all';

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Pengaturan Grup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
                const SizedBox(height: 4),
                Text('Hanya Admin yang dapat mengubah izin grup ini.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 16),
                const Divider(height: 1),

                // Edit Info Setting
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note_rounded, color: _primaryColor),
                  title: const Text('Edit info grup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(
                    editInfoPerm == 'all' ? 'Semua anggota' : 'Hanya admin',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final selected = await _showPermissionPicker(
                      ctx,
                      title: 'Siapa yang dapat mengedit info grup?',
                      subtitle: 'Memilih siapa yang dapat mengubah nama, ikon, dan deskripsi grup.',
                      currentValue: editInfoPerm,
                    );
                    if (selected != null && selected != editInfoPerm) {
                      final res = await ApiService.updateGroupInfo(cleanId, editInfoPermission: selected);
                      if (res['success'] == true) {
                        setModalState(() => editInfoPerm = selected);
                        setState(() {
                          _groupData?['edit_info_permission'] = selected;
                        });
                      }
                    }
                  },
                ),
                const Divider(height: 1),

                // Send Messages Setting
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline_rounded, color: _primaryColor),
                  title: const Text('Kirim pesan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(
                    sendMessagesPerm == 'all' ? 'Semua anggota' : 'Hanya admin',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final selected = await _showPermissionPicker(
                      ctx,
                      title: 'Siapa yang dapat mengirim pesan?',
                      subtitle: 'Jika disetel ke Hanya Admin, anggota biasa tidak dapat mengirim pesan.',
                      currentValue: sendMessagesPerm,
                    );
                    if (selected != null && selected != sendMessagesPerm) {
                      final res = await ApiService.updateGroupInfo(cleanId, sendMessagesPermission: selected);
                      if (res['success'] == true) {
                        setModalState(() => sendMessagesPerm = selected);
                        setState(() {
                          _groupData?['send_messages_permission'] = selected;
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showPermissionPicker(BuildContext context, {
    required String title,
    required String subtitle,
    required String currentValue,
  }) async {
    String selected = currentValue;
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('Semua anggota'),
                value: 'all',
                groupValue: selected,
                activeColor: _primaryColor,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('Hanya admin'),
                value: 'admins_only',
                groupValue: selected,
                activeColor: _primaryColor,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMembersModal() async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty) return;

    final contacts = await DatabaseHelper().getContacts();
    final existingUserIds = _groupMembers.map((m) => m['id']?.toString()).toSet();
    final existingPhones = _groupMembers.map((m) => _normalizePhone(m['phone']?.toString())).toSet();

    // Filter kontak yang belum tergabung di grup
    final available = contacts.where((c) {
      final phone = _normalizePhone(c['phone_number']?.toString());
      final uid = c['server_user_id']?.toString() ?? c['user_id']?.toString();
      if (phone.isNotEmpty && existingPhones.contains(phone)) return false;
      if (uid != null && existingUserIds.contains(uid)) return false;
      return true;
    }).toList();

    if (!mounted) return;

    final selectedUserIds = <int>{};
    String searchQuery = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = available.where((c) {
            final name = (c['saved_name'] ?? '').toString().toLowerCase();
            final phone = (c['phone_number'] ?? '').toString().toLowerCase();
            final q = searchQuery.toLowerCase();
            return name.contains(q) || phone.contains(q);
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tambah Peserta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Cari kontak...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                  onChanged: (val) => setModalState(() => searchQuery = val),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Tidak ada kontak tersedia untuk ditambahkan', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final phone = c['phone_number']?.toString() ?? '';
                            final name = c['saved_name']?.toString() ?? phone;
                            final rawId = c['server_user_id'] ?? c['user_id'];
                            final userId = int.tryParse(rawId?.toString() ?? '');

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade100,
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryColor)),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(phone, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              trailing: Checkbox(
                                activeColor: _primaryColor,
                                value: userId != null && selectedUserIds.contains(userId),
                                onChanged: (checked) {
                                  if (userId == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Kontak ini belum memiliki akun Our Chat')),
                                    );
                                    return;
                                  }
                                  setModalState(() {
                                    if (checked == true) {
                                      selectedUserIds.add(userId);
                                    } else {
                                      selectedUserIds.remove(userId);
                                    }
                                  });
                                },
                              ),
                              onTap: () {
                                if (userId == null) return;
                                setModalState(() {
                                  if (selectedUserIds.contains(userId)) {
                                    selectedUserIds.remove(userId);
                                  } else {
                                    selectedUserIds.add(userId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                if (selectedUserIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final res = await ApiService.addGroupMembers(cleanId, selectedUserIds.toList());
                          if (res['success'] == true) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res['message'] ?? 'Berhasil menambahkan anggota!'), backgroundColor: Colors.green),
                              );
                              _refreshGroupData(cleanId);
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res['message'] ?? 'Gagal menambahkan anggota'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        child: Text('Tambah ${selectedUserIds.length} Peserta ke Grup', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showMemberActions(Map<String, dynamic> member) async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty) return;

    final isMe = member['is_me'] == true;
    final isTargetAdmin = member['is_admin'] == true;
    final isTargetCreator = member['is_creator'] == true;
    final name = member['display_name'] ?? 'Anggota';
    final phone = member['phone'] ?? '';
    final memberId = member['id'];

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isTargetAdmin ? Colors.green.shade100 : Colors.blue.shade100,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: 18)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (phone.isNotEmpty) Text(phone, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (isTargetCreator)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                      child: Text('Pembuat Grup', style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                    )
                  else if (isTargetAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
                      child: Text('Admin Grup', style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              if (!isMe && phone.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded, color: _primaryColor),
                  title: Text('Chat Pribadi dengan $name'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openPrivateChatWithMember(phone, name, member['profile_pic']);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.call_outlined, color: Colors.green),
                  title: Text('Panggil $name'),
                  onTap: () {
                    Navigator.pop(ctx);
                    CallManager.instance.startCall(phone, name, false);
                  },
                ),
              ],

              // Admin-only management actions
              if (_isCurrentUserAdmin && !isMe) ...[
                const Divider(height: 1),

                // Promote / Demote
                if (!isTargetAdmin)
                  ListTile(
                    leading: const Icon(Icons.shield_outlined, color: Colors.blueAccent),
                    title: const Text('Jadikan Admin Grup'),
                    subtitle: const Text('Anggota ini akan dapat mengubah info dan mengelola anggota grup'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await _showConfirmDialog(
                        title: 'Jadikan Admin Grup?',
                        message: 'Apakah Anda yakin ingin mengangkat $name menjadi Admin grup ini?',
                        confirmText: 'Jadikan Admin',
                        confirmColor: Colors.blueAccent,
                      );
                      if (confirm == true) {
                        final res = await ApiService.updateGroupMemberRole(cleanId, memberId, role: 'admin');
                        if (res['success'] == true) {
                          _refreshGroupData(cleanId);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? '$name berhasil diangkat menjadi Admin!'), backgroundColor: Colors.green));
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal mengubah status admin'), backgroundColor: Colors.red));
                        }
                      }
                    },
                  )
                else if (isTargetAdmin && !isTargetCreator)
                  ListTile(
                    leading: Icon(Icons.remove_moderator_outlined, color: Colors.orange.shade800),
                    title: const Text('Hapus sebagai Admin'),
                    subtitle: const Text('Cabut jabatan admin dan jadikan anggota biasa'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await _showConfirmDialog(
                        title: 'Hapus sebagai Admin?',
                        message: 'Apakah Anda yakin ingin mencabut status admin dari $name?',
                        confirmText: 'Cabut Admin',
                        confirmColor: Colors.orange.shade800,
                      );
                      if (confirm == true) {
                        final res = await ApiService.updateGroupMemberRole(cleanId, memberId, role: 'member');
                        if (res['success'] == true) {
                          _refreshGroupData(cleanId);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Status admin berhasil dicabut'), backgroundColor: Colors.green));
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal mencabut status admin'), backgroundColor: Colors.red));
                        }
                      }
                    },
                  ),

                // Kick / Keluarkan
                if (isTargetCreator)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pembuat grup tidak dapat dikeluarkan atau dicabut status adminnya oleh admin lain.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                    title: Text('Keluarkan dari Grup', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    subtitle: Text('Keluarkan $name dari grup ini'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await _showConfirmDialog(
                        title: 'Keluarkan Anggota?',
                        message: 'Apakah Anda yakin ingin mengeluarkan $name dari grup ini?',
                        confirmText: 'Keluarkan',
                        confirmColor: Colors.redAccent,
                      );
                      if (confirm == true) {
                        final res = await ApiService.removeGroupMember(cleanId, memberId);
                        if (res['success'] == true) {
                          _refreshGroupData(cleanId);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? '$name berhasil dikeluarkan dari grup'), backgroundColor: Colors.green));
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal mengeluarkan anggota'), backgroundColor: Colors.red));
                        }
                      }
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshGroupData(String cleanId) async {
    final contacts = await DatabaseHelper().getContacts();
    final contactsMap = <String, String>{};
    for (var c in contacts) {
      final p = _normalizePhone(c['phone_number']?.toString());
      if (p.isNotEmpty) contactsMap[p] = c['saved_name']?.toString() ?? '';
    }
    _loadGroupDataAndMedia(cleanId, contactsMap);
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeaveGroup() async {
    final cleanId = (_resolvedRoomId ?? widget.roomId ?? '').replaceFirst('group_', '');
    if (cleanId.isEmpty || _myUserId == null) return;

    final confirm = await _showConfirmDialog(
      title: 'Keluar dari Grup?',
      message: _isCurrentUserCreator
          ? 'Anda adalah Pembuat Grup "$_displayName". Jika keluar, grup tetap aktif tetapi Anda tidak lagi menjadi anggota di dalamnya. Yakin ingin keluar?'
          : 'Apakah Anda yakin ingin keluar dari grup "$_displayName"? Anda tidak akan dapat membaca atau mengirim pesan lagi.',
      confirmText: 'Keluar',
      confirmColor: Colors.redAccent,
    );

    if (confirm == true) {
      final res = await ApiService.removeGroupMember(cleanId, _myUserId!);
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anda telah keluar dari grup'), backgroundColor: Colors.green),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Gagal keluar dari grup'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildHeaderSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar rounded square border radius 15px with photo change option for groups
          GestureDetector(
            onTap: (widget.isGroup && _canEditGroupInfo) ? _pickAndUploadGroupPhoto : null,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: widget.isGroup
                        ? Colors.orange.shade100
                        : (_isSavedLocally ? Colors.green.shade100 : Colors.blue.shade100),
                    child: _profilePic != null && _profilePic!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: ApiService.getServerUrl(_profilePic!),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (context, url, error) => _buildAvatarFallback(),
                          )
                        : _buildAvatarFallback(),
                  ),
                ),
                if (widget.isGroup && _canEditGroupInfo)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // User / Group Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayName,
                        style: const TextStyle(
                          color: _primaryColor,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isGroup && _canEditGroupInfo)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: _primaryColor, size: 20),
                        tooltip: 'Ubah Nama Grup',
                        padding: const EdgeInsets.only(left: 6),
                        constraints: const BoxConstraints(),
                        onPressed: _editGroupName,
                      ),
                  ],
                ),
                if (!widget.isGroup && _isSavedLocally && _originalName != null && _originalName != _displayName) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Nama: $_originalName',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  widget.isGroup 
                      ? 'Grup • ${_groupMembers.length} anggota'
                      : 'ID: ${_username ?? widget.phone}',
                  style: TextStyle(
                    color: widget.isGroup ? Colors.orange.shade800 : Colors.grey.shade500, 
                    fontSize: 13,
                    fontWeight: widget.isGroup ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback() {
    if (widget.isGroup) {
      return Center(
        child: Icon(Icons.group_rounded, size: 40, color: Colors.orange.shade800),
      );
    }
    return Center(
      child: Text(
        _displayName.isNotEmpty ? _displayName.substring(0, 1).toUpperCase() : '?',
        style: TextStyle(
          color: _isSavedLocally ? Colors.green.shade800 : _primaryColor,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final isMe = member['is_me'] == true;
    final isSaved = member['is_saved'] == true;
    final isCreator = member['is_creator'] == true;
    final isAdmin = member['is_admin'] == true;
    final displayName = member['display_name'] ?? 'User';
    final phone = member['phone'] ?? '';
    final profilePic = member['profile_pic'];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: widget.isGroup ? () => _showMemberActions(member) : null,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: isMe 
            ? _primaryColor.withOpacity(0.12)
            : isAdmin
                ? Colors.green.shade100
                : isSaved
                    ? Colors.teal.shade100
                    : Colors.blue.shade100,
        backgroundImage: (profilePic != null && profilePic.toString().isNotEmpty)
            ? NetworkImage(ApiService.getServerUrl(profilePic.toString()))
            : null,
        child: (profilePic == null || profilePic.toString().isEmpty)
            ? Text(
                displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '?',
                style: TextStyle(
                  color: isMe 
                      ? _primaryColor
                      : isAdmin
                          ? Colors.green.shade800
                          : isSaved
                              ? Colors.teal.shade800
                              : _primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isMe)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Anda',
                style: TextStyle(fontSize: 11, color: _primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
          if (isCreator)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200, width: 0.5),
              ),
              child: Text(
                'Pembuat',
                style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
              ),
            )
          else if (isAdmin)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300, width: 0.5),
              ),
              child: Text(
                'Admin Grup',
                style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ),
          if (!widget.isGroup && isSaved)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Kontak',
                style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      subtitle: phone.isNotEmpty
          ? Text(
              phone,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            )
          : null,
      trailing: widget.isGroup
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe && phone.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: _primaryColor, size: 20),
                    tooltip: 'Chat Pribadi',
                    onPressed: () => _openPrivateChatWithMember(phone, displayName, profilePic),
                  ),
                const Icon(Icons.more_vert_rounded, color: Colors.grey, size: 20),
              ],
            )
          : (!isMe && phone.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: _primaryColor, size: 20),
                  tooltip: 'Chat Pribadi',
                  onPressed: () => _openPrivateChatWithMember(phone, displayName, profilePic),
                )
              : null),
    );
  }

  Future<void> _openPrivateChatWithMember(String phone, String name, dynamic pic) async {
    final localRoomId = await DatabaseHelper().getLocalRoomId(phone);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ChatScreen(
          roomId: localRoomId ?? 'temp_$phone',
          otherUserName: name,
          otherUserPhone: phone,
          profilePic: pic?.toString(),
          isGroup: false,
        ),
      ),
    );
  }
}

// ============================================================================
// ROOM MEDIA GALLERY SCREEN (Foto & Video, Dokumen, Audio)
// ============================================================================
class RoomMediaGalleryScreen extends StatelessWidget {
  final String chatTitle;
  final List<Map<String, dynamic>> mediaList;

  const RoomMediaGalleryScreen({
    super.key,
    required this.chatTitle,
    required this.mediaList,
  });

  static const Color _primaryColor = Color(0xFF0F3460);

  @override
  Widget build(BuildContext context) {
    final imagesAndVideos = mediaList
        .where((m) => m['media_type'] == 'image' || m['media_type'] == 'video')
        .toList();
    final documents = mediaList.where((m) => m['media_type'] == 'file').toList();
    final audios = mediaList.where((m) => m['media_type'] == 'audio').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text('Media: $chatTitle', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'Foto & Video'),
              Tab(text: 'Dokumen'),
              Tab(text: 'Audio'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildImagesAndVideosGrid(context, imagesAndVideos),
            _buildDocumentsList(context, documents),
            _buildAudiosList(context, audios),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesAndVideosGrid(BuildContext context, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Belum ada foto atau video', style: TextStyle(color: Colors.grey)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final url = ApiService.getServerUrl(item['media_url'] ?? '');
        final isVideo = item['media_type'] == 'video';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 300),
                pageBuilder: (context, animation, secondaryAnimation) => FullMediaPreviewScreen(mediaItem: item),
                transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
                if (isVideo)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(Icons.play_circle_fill, color: Colors.white, size: 36),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocumentsList(BuildContext context, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Belum ada dokumen', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(color: Color(0xFFE5E7EB)),
      itemBuilder: (context, index) {
        final item = items[index];
        final fileName = (item['media_url'] ?? '').toString().split('/').last;

        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.insert_drive_file, color: _primaryColor),
          ),
          title: Text(
            fileName.isNotEmpty ? fileName : 'Dokumen ${index + 1}',
            style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            item['created_at']?.toString().split('T').first ?? '',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        );
      },
    );
  }

  Widget _buildAudiosList(BuildContext context, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Belum ada pesan audio', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(color: Color(0xFFE5E7EB)),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.mic, color: Colors.orange.shade800),
          ),
          title: Text(
            'Pesan Suara ${index + 1}',
            style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            item['created_at']?.toString().split('T').first ?? '',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        );
      },
    );
  }
}

// ============================================================================
// FULL MEDIA PREVIEW SCREEN (Lihat Foto / Putar Video)
// ============================================================================
class FullMediaPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> mediaItem;

  const FullMediaPreviewScreen({super.key, required this.mediaItem});

  @override
  State<FullMediaPreviewScreen> createState() => _FullMediaPreviewScreenState();
}

class _FullMediaPreviewScreenState extends State<FullMediaPreviewScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    if (widget.mediaItem['media_type'] == 'video') {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final url = ApiService.getServerUrl(widget.mediaItem['media_url'] ?? '');
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = ApiService.getServerUrl(widget.mediaItem['media_url'] ?? '');
    final isVideo = widget.mediaItem['media_type'] == 'video';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: isVideo
            ? (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator())
            : InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const CircularProgressIndicator(),
                  errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                ),
              ),
      ),
    );
  }
}
