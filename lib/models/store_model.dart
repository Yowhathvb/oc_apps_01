class StoreModel {
  final String id;
  final String ownerId;
  final String name;
  final String slug;
  final String description;
  final String? logo;
  final String? banner;

  StoreModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.slug,
    required this.description,
    this.logo,
    this.banner,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      id: json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'] ?? '',
      logo: json['logo'],
      banner: json['banner'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerId': ownerId,
      'name': name,
      'slug': slug,
      'description': description,
      'logo': logo,
      'banner': banner,
    };
  }
}
