import 'dart:convert';

class ProductModel {
  final String id;
  final String storeId;
  final String storeName;
  final String storeSlug;
  final String name;
  final String description;
  final double price;
  final int stock;
  final double weight; // Required
  final List<String> images;
  final Map<String, dynamic>? variants; // Optional

  ProductModel({
    required this.id,
    required this.storeId,
    this.storeName = '',
    this.storeSlug = '',
    required this.name,
    required this.description,
    required this.price,
    required this.stock,
    required this.weight,
    this.images = const [],
    this.variants,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? json['market_id']?.toString() ?? '',
      storeName: json['store_name']?.toString() ?? '',
      storeSlug: json['store_slug']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      stock: int.tryParse(json['stock']?.toString() ?? json['quantity']?.toString() ?? '0') ?? 0,
      weight: double.tryParse(json['weight']?.toString() ?? '0') ?? 0.0,
      images: _parseImages(json['media_urls'] ?? json['images']),
      variants: json['variants'] as Map<String, dynamic>?,
    );
  }

  static List<String> _parseImages(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => e.toString()).toList();
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is List) return parsed.map((e) => e.toString()).toList();
      } catch (e) {
        return [];
      }
    }
    return [];
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'storeId': storeId,
      'storeName': storeName,
      'storeSlug': storeSlug,
      'name': name,
      'description': description,
      'price': price,
      'stock': stock,
      'weight': weight,
      'images': images,
      'variants': variants,
    };
  }
}
