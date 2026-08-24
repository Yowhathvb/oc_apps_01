import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'register_store_screen.dart';
import 'add_product_screen.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({Key? key}) : super(key: key);

  @override
  _StoreDashboardScreenState createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  bool _isLoading = true;
  bool _hasStore = false;
  Map<String, dynamic>? _storeData;

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
    
    if (res['success'] && res['data']['store'] != null) {
      setState(() {
        _hasStore = true;
        _storeData = res['data']['store'];
        _isLoading = false;
      });
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_storeData?['name'] ?? 'Toko Saya'),
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
            ).then((_) => _checkStoreStatus()); // Refresh setelah tambah
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    // Placeholder untuk daftar produk toko
    return const Center(child: Text('Daftar Produk Toko Anda'));
  }

  Widget _buildOrdersTab() {
    // Placeholder untuk daftar pesanan masuk
    return const Center(child: Text('Belum ada pesanan masuk'));
  }

  Widget _buildSettingsTab() {
    // Placeholder untuk pengaturan toko
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Nama Toko: ${_storeData?['name']}'),
          const SizedBox(height: 8),
          Text('Deskripsi: ${_storeData?['description']}'),
        ],
      ),
    );
  }
}
