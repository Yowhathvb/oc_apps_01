class StoryViewer {
  final String userId;
  final String name;
  final String? phone;
  final String? profilePic;
  final DateTime viewedAt;

  StoryViewer({
    required this.userId,
    required this.name,
    this.phone,
    this.profilePic,
    required this.viewedAt,
  });

  factory StoryViewer.fromJson(Map<String, dynamic> json) {
    return StoryViewer(
      userId: json['userId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      phone: json['phone']?.toString(),
      profilePic: json['profilePic']?.toString(),
      viewedAt: json['viewedAt'] != null 
          ? DateTime.parse(json['viewedAt']) 
          : DateTime.now(),
    );
  }
}

class Story {
  final String id;
  final String userId;
  final String userName;
  final String? userPhone;
  final String? userProfilePic;
  final String contentType;
  final String? imageUrl;
  final String? videoUrl;
  final String? textContent;
  final String? backgroundColor;
  final String privacyType;
  final bool isViewed;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<StoryViewer> viewers;

  Story({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhone,
    this.userProfilePic,
    required this.contentType,
    this.imageUrl,
    this.videoUrl,
    this.textContent,
    this.backgroundColor,
    this.privacyType = 'kontak_saya',
    this.isViewed = false,
    required this.createdAt,
    required this.expiresAt,
    required this.viewers,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? 'Unknown',
      userPhone: json['userPhone']?.toString(),
      userProfilePic: json['userProfilePic']?.toString(),
      contentType: json['contentType']?.toString() ?? json['mediaType']?.toString() ?? 'image',
      imageUrl: json['imageUrl']?.toString() ?? (json['mediaType'] == 'image' ? json['mediaUrl'] : null),
      videoUrl: json['videoUrl']?.toString() ?? (json['mediaType'] == 'video' ? json['mediaUrl'] : null),
      textContent: json['textContent']?.toString() ?? json['caption']?.toString(),
      backgroundColor: json['backgroundColor']?.toString() ?? json['bgColor']?.toString(),
      privacyType: json['privacyType']?.toString() ?? 'kontak_saya',
      isViewed: json['isViewed'] == true || json['isViewed'] == 1,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']).toLocal() 
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null 
          ? DateTime.parse(json['expiresAt']).toLocal() 
          : DateTime.now(),
      viewers: json['viewers'] != null
          ? (json['viewers'] as List).map((v) => StoryViewer.fromJson(v)).toList()
          : [],
    );
  }
}

class UserStories {
  final String userId;
  final String userName;
  final String? userPhone;
  final String? userProfilePic;
  final List<Story> stories;

  UserStories({
    required this.userId,
    required this.userName,
    this.userPhone,
    this.userProfilePic,
    required this.stories,
  });

  factory UserStories.fromJson(Map<String, dynamic> json) {
    return UserStories(
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? 'Unknown',
      userPhone: json['userPhone']?.toString(),
      userProfilePic: json['userProfilePic']?.toString(),
      stories: json['stories'] != null
          ? (json['stories'] as List).map((s) => Story.fromJson(s)).toList()
          : [],
    );
  }
}
