import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product_model.dart';
import '../models/cart_model.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final ProductModel product; // Data awal dari daftar

  const ProductDetailScreen({Key? key, required this.product}) : super(key: key);

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isAdding = false;
  late ProductModel _fullProduct;
  bool _isLoading = true;
  List<ProductModel> _recommendations = [];
  int _cartItemCount = 0;

  @override
  void initState() {
    super.initState();
    _fullProduct = widget.product;
    _fetchProductDetail();
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

  Future<void> _fetchProductDetail() async {
    final res = await ApiService.getProductDetail(widget.product.id);
    if (res['success'] && mounted) {
      final data = res['data'];
      setState(() {
        if (data['product'] != null) {
          _fullProduct = ProductModel.fromJson(data['product']);
        }
        if (data['recommendations'] != null) {
          List recData = data['recommendations'];
          _recommendations = recData.map((e) => ProductModel.fromJson(e)).toList();
        }
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addToCart() async {
    setState(() {
      _isAdding = true;
    });

    final res = await ApiService.addToCart(_fullProduct.id, 1);
    
    setState(() {
      _isAdding = false;
    });

    if (res['success']) {
      _fetchCartCount(); // Update badge
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil ditambahkan ke keranjang')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Gagal menambahkan ke keranjang')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
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
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 300,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: _fullProduct.images.isNotEmpty
                      ? Image.network(
                          ApiService.getServerUrl(_fullProduct.images[0]),
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 100, color: Colors.grey),
                        )
                      : const Icon(Icons.image, size: 100, color: Colors.grey),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fullProduct.name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rp ${_fullProduct.price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 20, 
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w600
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.inventory, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('Stok: ${_fullProduct.stock}'),
                          const SizedBox(width: 16),
                          const Icon(Icons.monitor_weight, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('Berat: ${_fullProduct.weight} g'),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      // Store Info
                      if (_fullProduct.storeName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Colors.blueGrey,
                                child: Icon(Icons.store, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_fullProduct.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const Text('Penjual Terpercaya', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Kunjungi toko segera hadir!')),
                                  );
                                },
                                child: const Text('Kunjungi'),
                              )
                            ],
                          ),
                        ),

                      const Divider(height: 32),
                      const Text(
                        'Deskripsi Produk',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fullProduct.description.isNotEmpty ? _fullProduct.description : 'Tidak ada deskripsi',
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                      const Divider(height: 48),
                      const Text(
                        'Rekomendasi untuk Anda',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _recommendations.isEmpty 
                          ? const Text('Belum ada rekomendasi lainnya', style: TextStyle(color: Colors.grey))
                          : GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.75,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _recommendations.length,
                              itemBuilder: (context, index) {
                                final rec = _recommendations[index];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => ProductDetailScreen(product: rec)),
                                    );
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
                                            child: rec.images.isNotEmpty
                                                ? Image.network(
                                                    ApiService.getServerUrl(rec.images[0]),
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 40, color: Colors.grey),
                                                  )
                                                : const Icon(Icons.image, size: 40, color: Colors.grey),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                rec.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Rp ${rec.price.toStringAsFixed(0)}',
                                                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600, fontSize: 12),
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
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.chat),
                  color: Theme.of(context).primaryColor,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fitur chat dengan penjual segera hadir!')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () {
                    _addToCart(); 
                  },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Beli Langsung'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isAdding || _isLoading) ? null : _addToCart,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isAdding 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('+ Keranjang'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

