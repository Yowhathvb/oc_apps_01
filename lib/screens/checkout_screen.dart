import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/cart_model.dart';
import '../utils/format_utils.dart';

class CheckoutScreen extends StatefulWidget {
  final double totalAmount;
  final List<CartStoreModel> selectedStores;

  const CheckoutScreen({super.key, required this.totalAmount, required this.selectedStores});

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;

  void _submitCheckout() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.selectedStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada produk yang dipilih')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    List<String> cartItemIds = [];
    for (var store in widget.selectedStores) {
      cartItemIds.addAll(store.items.map((e) => e.cartId));
    }

    final res = await ApiService.checkout(
      cartItemIds,
      _addressController.text,
      _phoneController.text,
      _notesController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (res['success']) {
      // Tampilkan dialog sukses dan kembali ke home (hapus semua route di atas main)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Pesanan Berhasil'),
          content: const Text('Pesanan Anda (COD) telah berhasil dibuat dan sedang diproses.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('Kembali ke Beranda'),
            )
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Checkout gagal')),
      );
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
        key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alamat Pengiriman', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Alamat Lengkap',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Alamat tidak boleh kosong' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Nomor HP (Penerima)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Nomor HP tidak boleh kosong' : null,
              ),
              const SizedBox(height: 24),
              const Text('Rincian Pesanan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              ...widget.selectedStores.map((store) {
                double subtotal = 0;
                for (var item in store.items) {
                  subtotal += (item.price * item.cartQuantity);
                }
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.store, size: 20),
                            const SizedBox(width: 8),
                            Text(store.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ...store.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey[200],
                                child: (item.image != null && item.image!.isNotEmpty)
                                    ? Image.network(
                                        ApiService.getServerUrl(item.image!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, stack) => const Icon(Icons.image),
                                      )
                                    : const Icon(Icons.image),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(FormatUtils.formatRupiah(item.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('x', style: const TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal Produk', style: TextStyle(color: Colors.grey)),
                            Text(FormatUtils.formatRupiah(subtotal), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Pesan untuk Penjual (Opsional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal Produk:', style: TextStyle(color: Colors.grey)),
                          Text(FormatUtils.formatRupiah(widget.totalAmount)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Biaya Pengiriman:', style: TextStyle(color: Colors.grey)),
                          const Text('Dihitung kurir COD'),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Pembayaran:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            FormatUtils.formatRupiah(widget.totalAmount),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Pembayaran', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    FormatUtils.formatRupiah(widget.totalAmount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitCheckout,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: _isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Buat Pesanan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
