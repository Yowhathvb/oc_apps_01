class PostModel {
  final int id;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final String? authorAvatar;
  final String caption;
  final String? mediaUrl;
  final String mediaType;
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
    this.mediaUrl,
    required this.mediaType,
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

  factory PostModel.fromJson(Map<String, dynamic> json) {
    return PostModel(
      id: json['id'] as int,
      authorId: json['authorId'].toString(),
      authorName: json['authorName'] ?? 'Unknown',
      authorUsername: json['authorUsername'] ?? '',
      authorAvatar: json['authorAvatar'],
      caption: json['caption'] ?? '',
      mediaUrl: json['mediaUrl'],
      mediaType: json['mediaType'] ?? 'text',
      createdAt: DateTime.parse(json['createdAt']),
      likesCount: json['likesCount'] ?? 0,
      commentsCount: json['commentsCount'] ?? 0,
      sharesCount: json['sharesCount'] ?? 0,
      savesCount: json['savesCount'] ?? 0,
      isLiked: json['isLiked'] == 1 || json['isLiked'] == true,
      isFollowing: json['isFollowing'] == 1 || json['isFollowing'] == true,
      isShared: json['isShared'] == 1 || json['isShared'] == true,
      isSaved: json['isSaved'] == 1 || json['isSaved'] == true,
    );
  }
}
