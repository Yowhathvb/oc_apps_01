import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product_model.dart';
import '../models/cart_model.dart';
import '../utils/format_utils.dart';
import 'cart_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductDetailScreen extends StatefulWidget {
  final ProductModel product; // Data awal dari daftar

  const ProductDetailScreen({super.key, required this.product});

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isAdding = false;
  late ProductModel _fullProduct;
  bool _isLoading = true;
  List<ProductModel> _recommendations = [];
  int _cartItemCount = 0;
  String? _currentUserId;
  String? _myStoreId;

  @override
  void initState() {
    super.initState();
    _fullProduct = widget.product;
    _fetchProductDetail();
    _fetchCartCount();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    
    String? storeId;
    try {
      final res = await ApiService.getStoreStatus();
      if (res['success'] && res['data'] != null && res['data']['store'] != null) {
        storeId = res['data']['store']['id']?.toString() ?? res['data']['store']['market_id']?.toString();
      }
    } catch (e) {
      // ignore
    }
    
    if (mounted) {
      setState(() {
        _currentUserId = userId;
        _myStoreId = storeId;
      });
    }
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

  void _addToCart({int quantity = 1, Map<String, dynamic>? selectedVariants, bool isBuyNow = false}) async {
    setState(() {
      _isAdding = true;
    });

    final res = await ApiService.addToCart(_fullProduct.id, quantity, variants: selectedVariants);
    
    setState(() {
      _isAdding = false;
    });

    if (res['success']) {
      _fetchCartCount(); // Update badge
      if (isBuyNow) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CartScreen()),
        ).then((_) => _fetchCartCount());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Berhasil ditambahkan ke keranjang')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Gagal menambahkan ke keranjang')),
      );
    }
  }

  void _handleAction(bool isBuyNow) {
    if (_fullProduct.variants != null && 
       ((_fullProduct.variants!['warna'] != null && (_fullProduct.variants!['warna'] as List).isNotEmpty) || 
        (_fullProduct.variants!['ukuran'] != null && (_fullProduct.variants!['ukuran'] as List).isNotEmpty))) {
      _showVariantSelection(isBuyNow);
    } else {
      _addToCart(isBuyNow: isBuyNow);
    }
  }

  void _showVariantSelection(bool isBuyNow) {
    String? selectedWarna;
    String? selectedUkuran;
    int quantity = 1;

    final warnaList = _fullProduct.variants != null && _fullProduct.variants!['warna'] != null
        ? List<String>.from(_fullProduct.variants!['warna'])
        : <String>[];
    final ukuranList = _fullProduct.variants != null && _fullProduct.variants!['ukuran'] != null
        ? List<String>.from(_fullProduct.variants!['ukuran'])
        : <String>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 80,
                        width: 80,
                        color: Colors.grey[200],
                        child: _fullProduct.images.isNotEmpty
                            ? Image.network(
                                ApiService.getServerUrl(_fullProduct.images[0]),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(Icons.image),
                              )
                            : const Icon(Icons.image),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FormatUtils.formatRupiah(_fullProduct.price),
                              style: TextStyle(
                                fontSize: 18,
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Stok: ${_fullProduct.stock}'),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const Divider(),
                  if (warnaList.isNotEmpty) ...[
                    const Text('Warna', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: warnaList.map((w) {
                        final isSelected = selectedWarna == w;
                        return ChoiceChip(
                          label: Text(w),
                          selected: isSelected,
                          onSelected: (val) {
                            setModalState(() {
                              selectedWarna = val ? w : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (ukuranList.isNotEmpty) ...[
                    const Text('Ukuran', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ukuranList.map((u) {
                        final isSelected = selectedUkuran == u;
                        return ChoiceChip(
                          label: Text(u),
                          selected: isSelected,
                          onSelected: (val) {
                            setModalState(() {
                              selectedUkuran = val ? u : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Jumlah', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: quantity > 1
                            ? () => setModalState(() => quantity--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$quantity', style: const TextStyle(fontSize: 16)),
                      IconButton(
                        onPressed: quantity < _fullProduct.stock
                            ? () => setModalState(() => quantity++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        if (warnaList.isNotEmpty && selectedWarna == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pilih warna terlebih dahulu')),
                          );
                          return;
                        }
                        if (ukuranList.isNotEmpty && selectedUkuran == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pilih ukuran terlebih dahulu')),
                          );
                          return;
                        }

                        Navigator.pop(context);
                        
                        Map<String, dynamic> variants = {};
                        if (selectedWarna != null) variants['warna'] = selectedWarna;
                        if (selectedUkuran != null) variants['ukuran'] = selectedUkuran;

                        _addToCart(quantity: quantity, selectedVariants: variants.isEmpty ? null : variants, isBuyNow: isBuyNow);
                      },
                      child: Text(isBuyNow ? 'Beli Sekarang' : 'Masukkan Keranjang'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(flex: 3, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildVariantChips(String title, List<String> variants) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: variants.map((v) {
            Color baseColor;
            switch (v) {
              case 'Merah': baseColor = Colors.red; break;
              case 'Jingga': baseColor = Colors.orange; break;
              case 'Kuning': baseColor = Colors.yellow.shade700; break;
              case 'Hijau': baseColor = Colors.green; break;
              case 'Biru Muda': baseColor = Colors.lightBlue; break;
              case 'Biru Tua': baseColor = Colors.blue.shade900; break;
              case 'Nila': baseColor = Colors.indigo; break;
              case 'Ungu': baseColor = Colors.purple; break;
              default: baseColor = Theme.of(context).primaryColor;
            }
            if (title.toLowerCase() != 'warna') {
              baseColor = Theme.of(context).primaryColor;
            }

            return Chip(
              label: Text(v, style: TextStyle(color: baseColor, fontSize: 12)),
              backgroundColor: baseColor.withValues(alpha: 0.1),
              side: BorderSide(color: baseColor.withValues(alpha: 0.5)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMyProduct = (_myStoreId != null && _myStoreId == _fullProduct.storeId) || 
                        (_currentUserId != null && _currentUserId == _fullProduct.storeId);
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
                        FormatUtils.formatRupiah(_fullProduct.price),
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
                      
                      const SizedBox(height: 16),
                      // Details Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Spesifikasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            if (_fullProduct.sku.isNotEmpty)
                              _buildSpecRow('SKU', _fullProduct.sku),
                            _buildSpecRow('Kondisi', _fullProduct.conditionStatus),
                            if (_fullProduct.isPreorder)
                              _buildSpecRow('Pre-Order', 'Dikirim dalam ${_fullProduct.preorderDays} hari'),
                            if (_fullProduct.length > 0)
                              _buildSpecRow('Dimensi', '${_fullProduct.length} x ${_fullProduct.width} x ${_fullProduct.height} cm'),
                          ],
                        ),
                      ),
                      
                      // Variations
                      if (_fullProduct.variants != null && (_fullProduct.variants!['warna'] != null || _fullProduct.variants!['ukuran'] != null)) ...[
                        const SizedBox(height: 16),
                        const Text('Pilihan Variasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (_fullProduct.variants!['warna'] != null && (_fullProduct.variants!['warna'] as List).isNotEmpty)
                          _buildVariantChips('Warna', List<String>.from(_fullProduct.variants!['warna'])),
                        if (_fullProduct.variants!['ukuran'] != null && (_fullProduct.variants!['ukuran'] as List).isNotEmpty)
                          _buildVariantChips('Ukuran', List<String>.from(_fullProduct.variants!['ukuran'])),
                      ],

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
                                                FormatUtils.formatRupiah(rec.price),
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
          child: isMyProduct 
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Ini adalah produk Anda sendiri', 
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)
                ),
              )
            : Row(
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
                    _handleAction(true);
                  },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Beli Langsung'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isAdding || _isLoading) ? null : () => _handleAction(false),
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

