import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';

class PollVotesScreen extends StatefulWidget {
  final String groupId;
  final dynamic pollId;
  final String? initialQuestion;

  const PollVotesScreen({
    super.key,
    required this.groupId,
    required this.pollId,
    this.initialQuestion,
  });

  @override
  State<PollVotesScreen> createState() => _PollVotesScreenState();
}

class _PollVotesScreenState extends State<PollVotesScreen> {
  static const Color _primaryColor = Color(0xFF0F3460);

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _pollData;
  Map<String, String> _contactMap = {};

  @override
  void initState() {
    super.initState();
    _loadContactsAndDetails();
  }

  String _normalizePhone(String? p) {
    if (p == null) return '';
    String num = p.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (num.startsWith('62')) {
      return '0${num.substring(2)}';
    }
    return num;
  }

  Future<void> _loadContactsAndDetails() async {
    setState(() => _isLoading = true);

    // 1. Muat kontak lokal
    try {
      final contacts = await DatabaseHelper().getContacts();
      final map = <String, String>{};
      for (var c in contacts) {
        final p = _normalizePhone(c['phone_number']?.toString());
        if (p.isNotEmpty) {
          map[p] = c['saved_name']?.toString() ?? '';
        }
      }
      _contactMap = map;
    } catch (e) {
      debugPrint('[PollVotes] Gagal load kontak: $e');
    }

    // 2. Ambil detail polling
    final cleanId = widget.groupId.replaceFirst('group_', '');
    final res = await ApiService.getGroupPollDetails(cleanId, widget.pollId);

    if (mounted) {
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _pollData = Map<String, dynamic>.from(res['data']);
          _isLoading = false;
          _error = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = res['message'] ?? 'Gagal memuat detail suara';
        });
      }
    }
  }

  String _formatVotedTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _pollData?['question'] ?? widget.initialQuestion ?? 'Polling';
    final totalVoters = _pollData?['total_voters'] ?? 0;
    final List options = _pollData?['options'] as List? ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Detail Suara', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadContactsAndDetails,
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  children: [
                    // Header Pertanyaan
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$totalVoters orang telah memilih',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Opsi & Pemilih
                    ...options.map((opt) {
                      final String optText = opt['text']?.toString() ?? opt['option_text']?.toString() ?? '';
                      final int voteCount = (opt['vote_count'] is int) 
                          ? opt['vote_count'] 
                          : int.tryParse(opt['vote_count']?.toString() ?? '0') ?? 0;
                      final List voters = opt['voters'] as List? ?? [];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Option Title Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.05),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      optText,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: _primaryColor,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _primaryColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$voteCount suara',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // List of voters
                            if (voters.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Text(
                                  'Belum ada suara untuk opsi ini',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontStyle: FontStyle.italic),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: voters.length,
                                separatorBuilder: (context, index) => Divider(height: 1, indent: 64, color: Colors.grey.shade100),
                                itemBuilder: (ctx, i) {
                                  final v = voters[i];
                                  final rawPhone = v['phone']?.toString() ?? '';
                                  final normPhone = _normalizePhone(rawPhone);
                                  final localName = _contactMap[normPhone];
                                  final String voterName = (localName != null && localName.trim().isNotEmpty)
                                      ? localName.trim()
                                      : (v['name'] ?? normPhone);
                                  final pic = v['profile_pic']?.toString();
                                  final timeStr = _formatVotedTime(v['voted_at']?.toString());

                                  return ListTile(
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.blue.shade100,
                                      backgroundImage: (pic != null && pic.isNotEmpty)
                                          ? CachedNetworkImageProvider(ApiService.getServerUrl(pic))
                                          : null,
                                      child: (pic == null || pic.isEmpty)
                                          ? Text(
                                              voterName.isNotEmpty ? voterName[0].toUpperCase() : '?',
                                              style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      voterName,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: normPhone.isNotEmpty
                                        ? Text(normPhone, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                                        : null,
                                    trailing: timeStr.isNotEmpty
                                        ? Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))
                                        : null,
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}
