import 'dart:convert';

class PostModel {
  final int id;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final String? authorAvatar;
  final String caption;
  final Map<String, dynamic>? poll;
  final String? mediaUrl;
  final String? streamUrl;
  final String? thumbnailUrl;
  final String mediaType;
  final double? duration;
  final int? width;
  final int? height;
  final int? originalSize;
  final int? compressedSize;
  final int? compressionSavedPercent;
  int viewsCount;
  final DateTime createdAt;
  int likesCount;
  int commentsCount;
  int sharesCount;
  int savesCount;
  bool isLiked;
  bool isFollowing;
  bool isShared;
  bool isSaved;

  PostModel({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorUsername,
    this.authorAvatar,
    required this.caption,
    this.poll,
    this.mediaUrl,
    this.streamUrl,
    this.thumbnailUrl,
    required this.mediaType,
    this.duration,
    this.width,
    this.height,
    this.originalSize,
    this.compressedSize,
    this.compressionSavedPercent,
    this.viewsCount = 0,
    required this.createdAt,
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    this.savesCount = 0,
    required this.isLiked,
    this.isFollowing = false,
    this.isShared = false,
    this.isSaved = false,
  });

  String get effectiveVideoPath {
    if (streamUrl != null && streamUrl!.isNotEmpty) return streamUrl!;
    return mediaUrl ?? '';
  }

  double? get videoAspectRatio {
    if (width != null && height != null && width! > 0 && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  static int? _toInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString());
  }

  static double? _toDouble(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString());
  }

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final originalSize = _toInt(json['originalSize'] ?? json['original_size']);
    final compressedSize = _toInt(
      json['compressedSize'] ?? json['compressed_size'],
    );
    int? savedPercent = _toInt(json['compressionSavedPercent']);
    if (savedPercent == null &&
        originalSize != null &&
        compressedSize != null &&
        originalSize > 0) {
      savedPercent = (((originalSize - compressedSize) / originalSize) * 100)
          .round()
          .clamp(0, 100);
    }

    var mediaType = (json['mediaType'] ?? json['media_type'] ?? 'text')
        .toString();
    final rawMediaUrl = (json['mediaUrl'] ?? json['media_url'])?.toString();
    if (mediaType != 'video' && rawMediaUrl != null && rawMediaUrl.isNotEmpty) {
      final lower = rawMediaUrl.toLowerCase();
      if (lower.contains('.mp3') || lower.contains('.m4a') || lower.contains('.wav') || lower.contains('.aac') || lower.contains('.ogg') || lower.contains('.flac')) {
        mediaType = 'audio';
      }
    }
    final id = _toInt(json['id']) ?? 0;
    final rawStreamUrl = json['streamUrl'] ?? json['stream_url'];

    Map<String, dynamic>? pollData;
    if (json['poll'] != null && json['poll'] is Map) {
      pollData = Map<String, dynamic>.from(json['poll']);
    } else if (json['poll_data'] != null) {
      try {
        final raw = json['poll_data'];
        if (raw is Map) {
          pollData = Map<String, dynamic>.from(raw);
        } else if (raw is String && raw.isNotEmpty) {
          pollData = Map<String, dynamic>.from(jsonDecode(raw));
        }
      } catch (_) {}
    }

    String finalCaption = (json['caption'] ?? json['content'] ?? '').toString();
    if (pollData == null && finalCaption.contains('📊 Polling:')) {
      final parsed = _tryParsePollFromText(finalCaption);
      if (parsed != null) {
        pollData = parsed['poll'] as Map<String, dynamic>?;
        finalCaption = parsed['cleanCaption'] as String? ?? '';
      }
    }

    return PostModel(
      id: id,
      authorId: (json['authorId'] ?? json['author_id'] ?? '').toString(),
      authorName: (json['authorName'] ?? json['author_name'] ?? 'Unknown')
          .toString(),
      authorUsername: (json['authorUsername'] ?? json['author_username'] ?? '')
          .toString(),
      authorAvatar: json['authorAvatar'] ?? json['author_avatar'],
      caption: finalCaption,
      poll: pollData,
      mediaUrl: json['mediaUrl'] ?? json['media_url'],
      streamUrl:
          rawStreamUrl?.toString() ??
          (mediaType == 'video' && id > 0
              ? '/api/v1/media/videos/$id/stream'
              : null),
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail_url'],
      mediaType: mediaType,
      duration: _toDouble(json['duration']),
      width: _toInt(json['width']),
      height: _toInt(json['height']),
      originalSize: originalSize,
      compressedSize: compressedSize,
      compressionSavedPercent: savedPercent,
      viewsCount: _toInt(json['viewsCount'] ?? json['views_count']) ?? 0,
      createdAt:
          DateTime.tryParse(
            (json['createdAt'] ?? json['created_at'] ?? '').toString(),
          ) ??
          DateTime.now(),
      likesCount: _toInt(json['likesCount'] ?? json['likes_count']) ?? 0,
      commentsCount:
          _toInt(json['commentsCount'] ?? json['comments_count']) ?? 0,
      sharesCount: _toInt(json['sharesCount'] ?? json['shares_count']) ?? 0,
      savesCount: _toInt(json['savesCount'] ?? json['saves_count']) ?? 0,
      isLiked: json['isLiked'] == 1 || json['isLiked'] == true,
      isFollowing: json['isFollowing'] == 1 || json['isFollowing'] == true,
      isShared: json['isShared'] == 1 || json['isShared'] == true,
      isSaved: json['isSaved'] == 1 || json['isSaved'] == true,
    );
  }

  static Map<String, dynamic>? _tryParsePollFromText(String text) {
    try {
      final lines = text.split('\n').map((l) => l.trim()).toList();
      final pollIdx = lines.indexWhere((l) => l.startsWith('📊 Polling:'));
      if (pollIdx == -1) return null;

      final question = lines[pollIdx].replaceFirst('📊 Polling:', '').trim();
      final options = <Map<String, dynamic>>[];
      final cleanLines = <String>[];

      for (int i = 0; i < pollIdx; i++) {
        if (lines[i].isNotEmpty) cleanLines.add(lines[i]);
      }

      int optId = 1;
      for (int i = pollIdx + 1; i < lines.length; i++) {
        final line = lines[i];
        final match = RegExp(r'^\d+\.\s*(.+)$').firstMatch(line);
        if (match != null) {
          options.add({
            'id': optId++,
            'text': match.group(1)!.trim(),
            'vote_count': 0,
          });
        } else if (line.isNotEmpty) {
          cleanLines.add(line);
        }
      }

      if (options.length >= 2) {
        return {
          'cleanCaption': cleanLines.join('\n').trim(),
          'poll': {
            'id': 0,
            'question': question,
            'multiple_answers': false,
            'options': options,
            'total_voters': 0,
            'my_votes': <dynamic>[],
          },
        };
      }
    } catch (_) {}
    return null;
  }
}
