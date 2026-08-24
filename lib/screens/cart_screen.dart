import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/cart_model.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isLoading = true;
  CartModel? _cart;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchCart();
  }

  Future<void> _fetchCart() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final res = await ApiService.getCart();
    if (res['success']) {
      setState(() {
        _cart = CartModel.fromJson(res['data']['cart'] ?? res['data']);
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
        title: const Text('Keranjang'),
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
                        onPressed: _fetchCart,
                        child: const Text('Coba Lagi'),
                      )
                    ],
                  ),
                )
              : _cart == null || _cart!.isEmpty
                  ? const Center(child: Text('Keranjang belanja kosong'))
                  : ListView.builder(
                      itemCount: _cart!.allItems.length,
                      itemBuilder: (context, index) {
                        final item = _cart!.allItems[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: Container(
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
                            title: Text(item.name.isNotEmpty ? item.name : 'Produk tidak diketahui'),
                            subtitle: Text('Rp ${item.price.toStringAsFixed(0)} x ${item.cartQuantity}'),
                            trailing: Text(
                              'Rp ${(item.price * item.cartQuantity).toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: _cart != null && !_cart!.isEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
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
                        const Text('Total Pembayaran', style: TextStyle(color: Colors.grey)),
                        Text(
                          'Rp ${_cart!.total.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CheckoutScreen(totalAmount: _cart!.total),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      child: const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
