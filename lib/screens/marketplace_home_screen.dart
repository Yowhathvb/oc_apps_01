import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product_model.dart';
import '../utils/format_utils.dart';
import '../models/cart_model.dart';
import 'product_detail_screen.dart';
import 'cart_screen.dart';

class MarketplaceHomeScreen extends StatefulWidget {
  const MarketplaceHomeScreen({super.key});

  @override
  _MarketplaceHomeScreenState createState() => _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends State<MarketplaceHomeScreen> {
  bool _isLoading = true;
  List<ProductModel> _products = [];
  String _error = '';
  bool _isSearching = false;
  String _searchQuery = '';
  int _cartItemCount = 0;

  List<ProductModel> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    return _products.where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchCartCount();
  }

  Future<void> _fetchCartCount() async {
    final res = await ApiService.getCart();
    if (res['success'] && mounted) {
      final cart = CartModel.fromJson(res['data']['cart'] ?? res['data']);
      setState(() {
        _cartItemCount = cart.allItems.length;
      });
    }
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final res = await ApiService.getPublicProducts();
    if (res['success']) {
      List data = res['data'] is List ? res['data'] : (res['data']['products'] ?? []);
      setState(() {
        _products = data.map((e) => ProductModel.fromJson(e)).toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = res['message'];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Cari produk...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              )
            : const Text('Marketplace'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CartScreen()),
                  ).then((_) => _fetchCartCount());
                },
              ),
              if (_cartItemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_cartItemCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
            ],
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error, style: const TextStyle(color: Colors.red)),
                      ElevatedButton(
                        onPressed: _fetchProducts,
                        child: const Text('Coba Lagi'),
                      )
                    ],
                  ),
                )
              : _filteredProducts.isEmpty
                  ? const Center(child: Text('Tidak ada produk yang sesuai'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProductDetailScreen(product: product),
                              ),
                            ).then((_) => _fetchCartCount());
                          },
                          child: Card(
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    color: Colors.grey[200],
                                    child: product.images.isNotEmpty
                                        ? Image.network(
                                            ApiService.getServerUrl(product.images[0]),
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 50, color: Colors.grey),
                                          )
                                        : const Icon(Icons.image, size: 50, color: Colors.grey),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        FormatUtils.formatRupiah(product.price),
                                        style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
