import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/cart_model.dart';
import '../utils/format_utils.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isLoading = true;
  CartModel? _cart;
  String _error = '';
  Set<String> _selectedCartIds = {};

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
        _selectedCartIds = _cart!.allItems.map((e) => e.cartId).toSet();
      });
    } else {
      setState(() {
        _error = res['message'];
        _isLoading = false;
      });
    }
  }

  double get _selectedTotalAmount {
    if (_cart == null) return 0;
    double t = 0;
    for (var item in _cart!.allItems) {
      if (_selectedCartIds.contains(item.cartId)) {
        t += item.price * item.cartQuantity;
      }
    }
    return t;
  }
  
  bool _isStoreSelected(CartStoreModel store) {
    return store.items.every((item) => _selectedCartIds.contains(item.cartId));
  }
  
  void _toggleStoreSelection(CartStoreModel store, bool? value) {
    setState(() {
      for (var item in store.items) {
        if (value == true) {
          _selectedCartIds.add(item.cartId);
        } else {
          _selectedCartIds.remove(item.cartId);
        }
      }
    });
  }
  
  bool get _isAllSelected {
    if (_cart == null || _cart!.isEmpty) return false;
    return _cart!.allItems.every((item) => _selectedCartIds.contains(item.cartId));
  }
  
  void _toggleAllSelection(bool? value) {
    setState(() {
      if (value == true) {
        _selectedCartIds = _cart!.allItems.map((e) => e.cartId).toSet();
      } else {
        _selectedCartIds.clear();
      }
    });
  }

  Future<void> _updateQuantity(String cartId, int currentQty, int delta) async {
    int newQty = currentQty + delta;
    if (newQty < 1) return;
    
    // Optimistic UI update
    setState(() {
      for (var s in _cart!.stores) {
        for (var i in s.items) {
          if (i.cartId == cartId) {
            i.cartQuantity = newQty;
          }
        }
      }
    });
    
    final res = await ApiService.updateCartItemQuantity(cartId, newQty);
    if (!res['success']) {
      // Revert if failed
      _fetchCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'])));
      }
    }
  }

  Future<void> _deleteItem(String cartId) async {
    final res = await ApiService.deleteCartItem(cartId);
    if (res['success']) {
      setState(() {
        _selectedCartIds.remove(cartId);
      });
      _fetchCart();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'])));
      }
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
                      itemCount: _cart!.stores.length,
                      itemBuilder: (context, index) {
                        final store = _cart!.stores[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Store Header
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _isStoreSelected(store),
                                      onChanged: (val) => _toggleStoreSelection(store, val),
                                    ),
                                    const Icon(Icons.store, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      store.storeName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              // Store Items
                              ...store.items.map((item) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: _selectedCartIds.contains(item.cartId),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedCartIds.add(item.cartId);
                                            } else {
                                              _selectedCartIds.remove(item.cartId);
                                            }
                                          });
                                        },
                                      ),
                                      Container(
                                        width: 80,
                                        height: 80,
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
                                            Text(
                                              item.name.isNotEmpty ? item.name : 'Produk tidak diketahui', 
                                              style: const TextStyle(fontSize: 14),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              FormatUtils.formatRupiah(item.price),
                                              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                // Quantity control
                                                Container(
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.grey.shade300),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      InkWell(
                                                        onTap: () => _updateQuantity(item.cartId, item.cartQuantity, -1),
                                                        child: const Padding(
                                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                          child: Text('-', style: TextStyle(fontSize: 18)),
                                                        ),
                                                      ),
                                                      Container(
                                                        decoration: BoxDecoration(
                                                          border: Border.symmetric(vertical: BorderSide(color: Colors.grey.shade300)),
                                                        ),
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                        child: Text(item.cartQuantity.toString()),
                                                      ),
                                                      InkWell(
                                                        onTap: () => _updateQuantity(item.cartId, item.cartQuantity, 1),
                                                        child: const Padding(
                                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                          child: Text('+', style: TextStyle(fontSize: 16)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                                  onPressed: () => _deleteItem(item.cartId),
                                                ),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: _cart != null && !_cart!.isEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _isAllSelected,
                          onChanged: _toggleAllSelection,
                        ),
                        const Text('Semua', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total:', style: TextStyle(fontSize: 12)),
                        Text(
                          FormatUtils.formatRupiah(_selectedTotalAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _selectedCartIds.isEmpty ? null : () {
                        List<CartStoreModel> selectedStores = [];
                        for (var s in _cart!.stores) {
                          var selectedInStore = s.items.where((i) => _selectedCartIds.contains(i.cartId)).toList();
                          if (selectedInStore.isNotEmpty) {
                            selectedStores.add(CartStoreModel(
                              storeId: s.storeId,
                              storeName: s.storeName,
                              items: selectedInStore
                            ));
                          }
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CheckoutScreen(
                              totalAmount: _selectedTotalAmount,
                              selectedStores: selectedStores,
                            ),
                          ),
                        ).then((_) => _fetchCart());
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: Text('Checkout ()'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
