import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../utils/format_utils.dart';

class OrderManagementScreen extends StatefulWidget {
  const OrderManagementScreen({super.key});

  @override
  _OrderManagementScreenState createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<dynamic> _allOrders = [];

  final List<String> _tabs = [
    'Semua',
    'Belum Bayar',
    'Perlu Dikirim',
    'Dikirim',
    'Selesai',
    'Dibatalkan'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getStoreOrders();
    if (res['success']) {
      setState(() {
        _allOrders = res['data'];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Gagal mengambil pesanan')),
        );
      }
    }
  }

  Future<void> _updateStatus(int orderId, String newStatus, {String? resi, String? proof}) async {
    final res = await ApiService.updateOrderStatus(orderId, newStatus, trackingNumber: resi, proof: proof);
    if (res['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status pesanan diperbarui')));
      }
      _fetchOrders();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal update status')));
      }
    }
  }

  void _showInputResiDialog(int orderId) {
    final resiController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Input Nomor Resi'),
        content: TextField(
          controller: resiController,
          decoration: const InputDecoration(labelText: 'Nomor Resi / Pelacakan'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (resiController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _updateStatus(orderId, 'shipped', resi: resiController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F3460), foregroundColor: Colors.white),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUploadProofDialog(int orderId) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Konfirmasi Penerimaan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Anda yakin barang sudah diterima? Berikut bukti yang akan diunggah:'),
              const SizedBox(height: 10),
              Image.file(File(pickedFile.path), height: 150),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateStatus(orderId, 'completed', proof: pickedFile.path);
              },
              child: const Text('Konfirmasi'),
            ),
          ],
        ),
      );
    }
  }

  List<dynamic> _filterOrders(String tabName) {
    if (tabName == 'Semua') return _allOrders;
    
    String status = '';
    switch (tabName) {
      case 'Belum Bayar': status = 'pending'; break;
      case 'Perlu Dikirim': status = 'processing'; break;
      case 'Dikirim': status = 'shipped'; break;
      case 'Selesai': status = 'completed'; break;
      case 'Dibatalkan': status = 'cancelled'; break;
    }
    
    return _allOrders.where((o) => o['status'] == status).toList();
  }

  Widget _buildOrderCard(dynamic order) {
    final status = order['status'];
    Color statusColor = Colors.grey;
    String statusText = 'Unknown';
    
    switch (status) {
      case 'pending': statusColor = Colors.orange; statusText = 'Belum Bayar'; break;
      case 'processing': statusColor = Colors.blue; statusText = 'Perlu Dikirim'; break;
      case 'shipped': statusColor = Colors.purple; statusText = 'Sedang Dikirim'; break;
      case 'completed': statusColor = Colors.green; statusText = 'Selesai'; break;
      case 'cancelled': statusColor = Colors.red; statusText = 'Dibatalkan'; break;
    }

    final items = order['items'] as List<dynamic>? ?? [];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order['buyer_name'] ?? 'Pembeli',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (order['shipping_address'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Alamat Pengiriman:\n${order['shipping_address']}',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(),
            ...items.map((item) {
              String? imgUrl;
              try {
                if (item['media_urls'] != null) {
                  final urls = jsonDecode(item['media_urls']);
                  if (urls is List && urls.isNotEmpty) {
                    imgUrl = urls[0].toString();
                  }
                }
              } catch (_) {}
              imgUrl ??= item['image'];
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.grey[200],
                        image: imgUrl != null
                          ? DecorationImage(image: NetworkImage(imgUrl), fit: BoxFit.cover)
                          : null,
                      ),
                      child: imgUrl == null ? const Icon(Icons.image, color: Colors.grey) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('x${item['quantity']}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(FormatUtils.formatRupiah(double.tryParse(item['price_at_time']?.toString() ?? '0') ?? 0)),
                  ],
                ),
              );
            }),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${items.length} produk', style: TextStyle(color: Colors.grey[600])),
                Row(
                  children: [
                    const Text('Total Pesanan: '),
                    Text(
                      FormatUtils.formatRupiah(double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F3460), fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _updateStatus(order['id'], 'processing'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F3460), foregroundColor: Colors.white),
                  child: const Text('Terima & Proses Pesanan'),
                ),
              ),
            ],
            if (status == 'processing') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showInputResiDialog(order['id']),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F3460), foregroundColor: Colors.white),
                  child: const Text('Kirim Pesanan'),
                ),
              ),
            ],
            if (status == 'shipped') ...[
              const SizedBox(height: 12),
              if (order['tracking_number'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('Resi: ${order['tracking_number']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showUploadProofDialog(order['id']),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text('Barang Diterima (Upload Bukti)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Pesanan Saya'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF0F3460),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF0F3460),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: _tabs.map((tab) {
              final filtered = _filterOrders(tab);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Belum ada pesanan', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _fetchOrders,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _buildOrderCard(filtered[index]);
                  },
                ),
              );
            }).toList(),
          ),
    );
  }
}
