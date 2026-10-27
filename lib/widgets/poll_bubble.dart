import 'package:flutter/material.dart';

class PollBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final Function(int optionId)? onVote;
  final VoidCallback? onViewVotes;

  const PollBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onVote,
    this.onViewVotes,
  });

  static const Color _primaryColor = Color(0xFF0F3460);
  static const Color _votedColor = Color(0xFF10B981); // Emerald green for checked options

  @override
  Widget build(BuildContext context) {
    final poll = message['poll'] as Map<String, dynamic>?;
    if (poll == null) {
      return Text(
        message['message'] ?? 'Polling',
        style: TextStyle(color: isMe ? Colors.white : Colors.black87),
      );
    }

    final String question = poll['question']?.toString() ?? message['message']?.toString() ?? 'Polling';
    final bool isMultiple = poll['multiple_answers'] == true || poll['multiple_answers'] == 1;
    final List<dynamic> options = poll['options'] as List<dynamic>? ?? [];
    final int totalVoters = (poll['total_voters'] is int) 
        ? poll['total_voters'] 
        : int.tryParse(poll['total_voters']?.toString() ?? '0') ?? 0;

    // Hitung total suara akumulatif dari opsi jika totalVoters 0
    int calculatedTotalVotes = 0;
    for (var opt in options) {
      final vc = (opt['vote_count'] is int) ? opt['vote_count'] as int : int.tryParse(opt['vote_count']?.toString() ?? '0') ?? 0;
      calculatedTotalVotes += vc;
    }
    final int effectiveTotal = totalVoters > calculatedTotalVotes ? totalVoters : calculatedTotalVotes;

    final textColor = isMe ? Colors.white : Colors.black87;
    final subtitleColor = isMe ? Colors.white70 : Colors.black54;

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 310),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Judul Pertanyaan Polling
          Text(
            question,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),

          // 2. Subtitle: Single Choice atau Multiple Choice
          Row(
            children: [
              Icon(
                isMultiple ? Icons.checklist_rounded : Icons.radio_button_checked_rounded,
                size: 13,
                color: subtitleColor,
              ),
              const SizedBox(width: 4),
              Text(
                isMultiple ? 'Pilih satu atau lebih' : 'Pilih satu',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Daftar Opsi Pilihan
          ...options.map((opt) {
            final int optionId = (opt['id'] is int) ? opt['id'] : int.tryParse(opt['id']?.toString() ?? '0') ?? 0;
            final String text = opt['text']?.toString() ?? opt['option_text']?.toString() ?? '';
            final int voteCount = (opt['vote_count'] is int) ? opt['vote_count'] : int.tryParse(opt['vote_count']?.toString() ?? '0') ?? 0;
            final bool isVotedByMe = opt['is_voted_by_me'] == true;

            final double percentage = effectiveTotal > 0 ? (voteCount / effectiveTotal) : 0.0;
            final int percentInt = (percentage * 100).round();

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isMe 
                    ? Colors.white.withOpacity(isVotedByMe ? 0.22 : 0.10)
                    : (isVotedByMe ? _votedColor.withOpacity(0.08) : Colors.black.withOpacity(0.03)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isVotedByMe 
                      ? (isMe ? Colors.white70 : _votedColor) 
                      : (isMe ? Colors.white24 : Colors.grey.shade300),
                  width: isVotedByMe ? 1.5 : 1.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onVote != null ? () => onVote!(optionId) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Indicator Icon (Radio / Checkbox)
                            Icon(
                              isMultiple
                                  ? (isVotedByMe ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                                  : (isVotedByMe ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                              size: 20,
                              color: isVotedByMe 
                                  ? (isMe ? Colors.white : _votedColor) 
                                  : (isMe ? Colors.white60 : Colors.grey.shade500),
                            ),
                            const SizedBox(width: 8),

                            // Option Text
                            Expanded(
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: isVotedByMe ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),

                            // Vote count badge
                            if (voteCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.white24 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$voteCount',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isMe ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Progress Bar & Percentage
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percentage,
                                  minHeight: 5,
                                  backgroundColor: isMe ? Colors.white24 : Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isVotedByMe 
                                        ? (isMe ? Colors.white : _votedColor) 
                                        : (isMe ? Colors.white60 : _primaryColor.withOpacity(0.5)),
                                  ),
                                ),
                              ),
                            ),
                            if (effectiveTotal > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '$percentInt%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: subtitleColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 4),
          Divider(
            height: 1, 
            thickness: 0.8, 
            color: isMe ? Colors.white24 : Colors.grey.shade300,
          ),
          const SizedBox(height: 4),

          // 4. Footer: Tombol "Lihat Suara"
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onViewVotes,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.how_to_vote_rounded,
                    size: 15,
                    color: isMe ? Colors.white : _primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Lihat suara (${totalVoters > 0 ? '$totalVoters suara' : 'Belum ada suara'})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isMe ? Colors.white : _primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
