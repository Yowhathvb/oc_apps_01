import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PostPollCard extends StatefulWidget {
  final int postId;
  final Map<String, dynamic> initialPoll;

  const PostPollCard({
    super.key,
    required this.postId,
    required this.initialPoll,
  });

  @override
  State<PostPollCard> createState() => _PostPollCardState();
}

class _PostPollCardState extends State<PostPollCard> {
  late Map<String, dynamic> _poll;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _poll = Map<String, dynamic>.from(widget.initialPoll);
  }

  @override
  void didUpdateWidget(covariant PostPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPoll != widget.initialPoll) {
      _poll = Map<String, dynamic>.from(widget.initialPoll);
    }
  }

  Future<void> _handleVote(int optionId) async {
    if (_isVoting) return;
    setState(() => _isVoting = true);

    // Optimistic update
    final prevPoll = Map<String, dynamic>.from(_poll);
    final myVotes = List<dynamic>.from(_poll['my_votes'] ?? []);
    final isMultiple = _poll['multiple_answers'] == true || _poll['multiple_answers'] == 1;

    if (isMultiple) {
      if (myVotes.contains(optionId)) {
        myVotes.remove(optionId);
      } else {
        myVotes.add(optionId);
      }
    } else {
      if (myVotes.contains(optionId)) {
        myVotes.clear();
      } else {
        myVotes.clear();
        myVotes.add(optionId);
      }
    }

    setState(() {
      _poll['my_votes'] = myVotes;
    });

    final res = await ApiService.votePostPoll(widget.postId, optionId);
    if (!mounted) return;

    if (res['success'] == true && res['poll'] != null) {
      setState(() {
        _poll = Map<String, dynamic>.from(res['poll']);
        _isVoting = false;
      });
    } else {
      setState(() {
        _poll = prevPoll;
        _isVoting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Gagal memberikan suara')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _poll['question']?.toString() ?? 'Polling';
    final options = (_poll['options'] as List<dynamic>? ?? []).map((o) => Map<String, dynamic>.from(o as Map)).toList();
    final myVotes = (_poll['my_votes'] as List<dynamic>? ?? []).map((v) => int.tryParse(v.toString()) ?? 0).toList();
    final isMultiple = _poll['multiple_answers'] == true || _poll['multiple_answers'] == 1;

    int totalVotes = 0;
    for (var opt in options) {
      final c = int.tryParse(opt['vote_count']?.toString() ?? '0') ?? 0;
      totalVotes += c;
    }
    final totalVoters = int.tryParse(_poll['total_voters']?.toString() ?? '0') ?? totalVotes;
    final effectiveTotal = totalVotes > 0 ? totalVotes : 1;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Pertanyaan
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.poll_rounded, color: Color(0xFF0F3460), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isMultiple ? 'Pilih satu atau lebih' : 'Pilih satu opsi',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Daftar Pilihan
          ...options.map((opt) {
            final optId = int.tryParse(opt['id']?.toString() ?? '0') ?? 0;
            final optText = opt['text']?.toString() ?? '';
            final count = int.tryParse(opt['vote_count']?.toString() ?? '0') ?? 0;
            final isSelected = myVotes.contains(optId);
            final percent = (totalVotes > 0 ? (count / effectiveTotal) * 100 : 0.0).clamp(0.0, 100.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _isVoting ? null : () => _handleVote(optId),
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0F3460) : const Color(0xFFCBD5E1),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Bar persentase pengisian
                      if (totalVotes > 0)
                        FractionallySizedBox(
                          widthFactor: percent / 100.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0F3460).withOpacity(0.18)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                        ),

                      // Konten Opsi
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? (isMultiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                                  : (isMultiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_off_rounded),
                              size: 18,
                              color: isSelected ? const Color(0xFF0F3460) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                optText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: const Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (totalVotes > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${percent.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? const Color(0xFF0F3460) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Footer info total suara
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              '$totalVoters suara${totalVotes > 0 ? ' • $totalVotes pilihan' : ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }
}
