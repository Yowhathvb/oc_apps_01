class CartItemModel {
  final String cartId;
  final String productId;
  final String name;
  final double price;
  final String? image;
  int cartQuantity;
  final int stockQuantity;

  CartItemModel({
    required this.cartId,
    required this.productId,
    required this.name,
    required this.price,
    this.image,
    required this.cartQuantity,
    required this.stockQuantity,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      cartId: json['cart_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      name: json['name'] ?? '',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      image: json['image'],
      cartQuantity: int.tryParse(json['cart_quantity']?.toString() ?? '1') ?? 1,
      stockQuantity: int.tryParse(json['stock_quantity']?.toString() ?? '0') ?? 0,
    );
  }
}

class CartStoreModel {
  final String storeId;
  final String storeName;
  final List<CartItemModel> items;

  CartStoreModel({
    required this.storeId,
    required this.storeName,
    required this.items,
  });

  factory CartStoreModel.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    return CartStoreModel(
      storeId: json['store_id']?.toString() ?? '',
      storeName: json['store_name'] ?? 'Toko',
      items: itemsList.map((i) => CartItemModel.fromJson(i)).toList(),
    );
  }
}

class CartModel {
  final List<CartStoreModel> stores;

  CartModel({required this.stores});

  factory CartModel.fromJson(dynamic json) {
    List<CartStoreModel> parsedStores = [];
    if (json is Map && json['cart'] is List) {
       parsedStores = (json['cart'] as List).map((e) => CartStoreModel.fromJson(e)).toList();
    } else if (json is List) {
       parsedStores = json.map((e) => CartStoreModel.fromJson(e)).toList();
    }
    return CartModel(stores: parsedStores);
  }

  double get total {
    double t = 0;
    for (var s in stores) {
      for (var i in s.items) {
        t += (i.price * i.cartQuantity);
      }
    }
    return t;
  }

  bool get isEmpty => stores.isEmpty;
  
  List<CartItemModel> get allItems {
    List<CartItemModel> all = [];
    for (var s in stores) {
      all.addAll(s.items);
    }
    return all;
  }
}
