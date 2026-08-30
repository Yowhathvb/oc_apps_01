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
  final double weight; 
  final List<String> images;
  final Map<String, dynamic>? variants; 
  final String sku;
  final String conditionStatus;
  final bool isPreorder;
  final int preorderDays;
  final double length;
  final double width;
  final double height;

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
    this.sku = '',
    this.conditionStatus = 'Baru',
    this.isPreorder = false,
    this.preorderDays = 0,
    this.length = 0,
    this.width = 0,
    this.height = 0,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parsedVariants;
    if (json['variations'] != null) {
      if (json['variations'] is String) {
        try {
          parsedVariants = jsonDecode(json['variations']);
        } catch (_) {}
      } else if (json['variations'] is Map) {
        parsedVariants = Map<String, dynamic>.from(json['variations']);
      }
    }

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
      variants: parsedVariants,
      sku: json['sku']?.toString() ?? '',
      conditionStatus: json['condition_status']?.toString() ?? 'Baru',
      isPreorder: json['is_preorder'] == 1 || json['is_preorder'] == true || json['is_preorder'] == 'true' || json['is_preorder'] == '1',
      preorderDays: int.tryParse(json['preorder_days']?.toString() ?? '0') ?? 0,
      length: double.tryParse(json['length']?.toString() ?? '0') ?? 0.0,
      width: double.tryParse(json['width']?.toString() ?? '0') ?? 0.0,
      height: double.tryParse(json['height']?.toString() ?? '0') ?? 0.0,
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
      'sku': sku,
      'conditionStatus': conditionStatus,
      'isPreorder': isPreorder,
      'preorderDays': preorderDays,
      'length': length,
      'width': width,
      'height': height,
    };
  }
}
