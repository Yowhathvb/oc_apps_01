import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'register_store_screen.dart';
import 'add_product_screen.dart';
import '../models/product_model.dart';
import 'product_detail_screen.dart';
import '../utils/format_utils.dart';
import 'order_management_screen.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({super.key});

  @override
  _StoreDashboardScreenState createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  bool _isLoading = true;
  bool _hasStore = false;
  Map<String, dynamic>? _storeData;
  List<ProductModel> _products = [];
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    _checkStoreStatus();
  }

  Future<void> _checkStoreStatus() async {
    setState(() {
      _isLoading = true;
    });
    
    final res = await ApiService.getStoreStatus();
    
    if (res['success'] && res['data']['hasStore'] == true) {
      setState(() {
        _hasStore = true;
        _storeData = res['data']['store'];
        _isLoading = false;
      });
      if (_storeData?['status'] == 'approved') {
        _fetchProducts();
      }
    } else {
      setState(() {
        _hasStore = false;
        _isLoading = false;
      });
      // Arahkan ke halaman pendaftaran jika belum punya toko
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RegisterStoreScreen()),
        );
      });
    }
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });
    final res = await ApiService.getStoreProducts();
    if (res['success']) {
      setState(() {
        _products = (res['data'] as List).map((p) => ProductModel.fromJson(p)).toList();
        _isLoadingProducts = false;
      });
    } else {
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  void _deleteProduct(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Produk'),
        content: const Text('Yakin ingin menghapus produk ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm == true) {
      final res = await ApiService.deleteStoreProduct(id);
      if (res['success']) {
        _fetchProducts();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk dihapus')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal menghapus')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasStore) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_storeData?['status'] == 'pending') {
      return Scaffold(
        appBar: AppBar(title: const Text('Status Toko')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('Toko Sedang Diverifikasi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Mohon tunggu persetujuan dari admin.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checkStoreStatus,
                child: const Text('Refresh Status'),
              )
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_storeData?['store_name'] ?? 'Toko Saya'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Produk'),
              Tab(text: 'Pesanan'),
              Tab(text: 'Pengaturan'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab Produk
            _buildProductsTab(),
            // Tab Pesanan
            _buildOrdersTab(),
            // Tab Pengaturan
            _buildSettingsTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddProductScreen()),
            ).then((_) => _fetchProducts()); // Refresh setelah tambah
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_products.isEmpty) {
      return const Center(child: Text('Belum ada produk. Tambahkan sekarang!'));
    }

    return ListView.builder(
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        final String? imageUrl = (product.images.isNotEmpty) ? product.images.first : null;
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              color: Colors.grey[200],
              child: imageUrl != null
                  ? Image.network(
                      ApiService.getServerUrl(imageUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => const Icon(Icons.image),
                    )
                  : const Icon(Icons.image),
            ),
            title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${FormatUtils.formatRupiah(product.price)} | Stok: ${product.stock}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () {
                    // Navigator.push Edit
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteProduct(product.id),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProductDetailScreen(product: product)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildOrdersTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.assignment, size: 64, color: Color(0xFF0F3460)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const OrderManagementScreen()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F3460), foregroundColor: Colors.white),
            child: const Text('Buka Manajemen Pesanan'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    // Placeholder untuk pengaturan toko
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Nama Toko: ${_storeData?['store_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Text('Deskripsi: ${_storeData?['description']}'),
        ],
      ),
    );
  }
}
