import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

import '../models/product_model.dart';

class EditProductScreen extends StatefulWidget {

  final ProductModel product;

  const EditProductScreen({super.key, required this.product});

  @override
  _EditProductScreenState createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Info Produk
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _category = 'Umum';
  
  // Info Jual
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _skuController = TextEditingController();
  
  // Variasi
  List<String> _selectedColors = [];
  List<String> _selectedSizes = [];
  final List<String> _availableColors = ['Merah', 'Jingga', 'Kuning', 'Hijau', 'Biru Muda', 'Biru Tua', 'Nila', 'Ungu'];
  final List<String> _availableSizes = ['S', 'M', 'L', 'XL', 'XXL'];

  // Pengiriman
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  // Lainnya
  String _condition = 'Baru';
  bool _isPreorder = false;
  final _preorderDaysController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingCategories = true;
  List<String> _categoriesList = ['Umum'];
  
  final List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    _nameController.text = widget.product.name;
    _descController.text = widget.product.description;
    _priceController.text = widget.product.price.toInt().toString();
    _stockController.text = widget.product.stock.toString();
    
    // We don't have sku, weight, condition etc in the provided map but we can parse variations if present
    try {
      if (widget.product.variants != null) {
        _selectedColors = List<String>.from(widget.product.variants!['warna'] ?? []);
        _selectedSizes = List<String>.from(widget.product.variants!['ukuran'] ?? []);
      }
    } catch (e) {}
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    final cats = await ApiService.getProductCategories();
    if (mounted) {
      setState(() {
        _categoriesList = cats.isNotEmpty ? cats : ['Umum'];
        if (!_categoriesList.contains(_category)) {
          _category = _categoriesList.first;
        }
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _pickImage() async {
    if (_selectedImages.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maksimal 9 foto')));
      return;
    }
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _selectedImages.add(File(image.path));
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    

    setState(() {
      _isLoading = true;
    });

    final variationsMap = {
      'warna': _selectedColors,
      'ukuran': _selectedSizes
    };

    final data = {
      'name': _nameController.text,
      'description': _descController.text,
      'category': _category,
      'price': _priceController.text,
      'quantity': _stockController.text,
      'sku': _skuController.text,
      'weight': _weightController.text,
      'length': _lengthController.text.isNotEmpty ? _lengthController.text : '0',
      'width': _widthController.text.isNotEmpty ? _widthController.text : '0',
      'height': _heightController.text.isNotEmpty ? _heightController.text : '0',
      'condition_status': _condition,
      'is_preorder': _isPreorder.toString(),
      'preorder_days': _isPreorder ? _preorderDaysController.text : '0',
      'variations': jsonEncode(variationsMap),
    };

    final List<String> imagePaths = _selectedImages.map((e) => e.path).toList();

    final res = await ApiService.editProduct(widget.product.id, data, imagePaths, []);

    setState(() {
      _isLoading = false;
    });

    if (res['success']) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk berhasil diperbarui')));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Gagal memperbarui produk')));
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false, int maxLines = 1, bool isRequired = false, String? prefixText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          prefixText: prefixText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        validator: isRequired ? (v) => v == null || v.isEmpty ? 'Wajib diisi' : null : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Edit Produk'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          _isLoading 
            ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                icon: const Icon(Icons.check, color: Colors.blue),
                onPressed: _submitProduct,
              )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          children: [
            // MEDIA SECTION
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Foto Produk *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${_selectedImages.length}/9', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length < 9 ? _selectedImages.length + 1 : 9,
                      itemBuilder: (context, index) {
                        if (index == _selectedImages.length) {
                          return GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.5), style: BorderStyle.solid),
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.blue.shade50,
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, color: Colors.blue),
                                  SizedBox(height: 4),
                                  Text('Tambah Foto', style: TextStyle(color: Colors.blue, fontSize: 10)),
                                ],
                              ),
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300),
                                image: DecorationImage(
                                  image: FileImage(_selectedImages[index]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            if (index == 0)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 8,
                                child: Container(
                                  color: Colors.black54,
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: const Text('Foto Utama', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                              ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: GestureDetector(
                                onTap: () => _removeImage(index),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // INFORMASI PRODUK
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Informasi Produk'),
                  _buildTextField('Nama Produk', _nameController, isRequired: true),
                  _buildTextField('Deskripsi Produk', _descController, maxLines: 4, isRequired: true),
                  _isLoadingCategories
                      ? const CircularProgressIndicator()
                      : DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                          items: _categoriesList
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) => setState(() => _category = v!),
                        ),
                ],
              ),
            ),

            // INFORMASI PENJUALAN
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Informasi Penjualan'),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Harga', _priceController, isNumber: true, isRequired: true, prefixText: 'Rp ')),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTextField('Stok', _stockController, isNumber: true, isRequired: true)),
                    ],
                  ),
                  _buildTextField('SKU Induk (Opsional)', _skuController),
                  const Divider(),
                  const Text('Variasi', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Warna:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Wrap(
                    spacing: 8,
                    children: _availableColors.map((color) {
                      final isSelected = _selectedColors.contains(color);
                      // Use theme colors
                      Color baseColor;
                      switch (color) {
                        case 'Merah': baseColor = Colors.red; break;
                        case 'Jingga': baseColor = Colors.orange; break;
                        case 'Kuning': baseColor = Colors.yellow.shade700; break;
                        case 'Hijau': baseColor = Colors.green; break;
                        case 'Biru Muda': baseColor = Colors.lightBlue; break;
                        case 'Biru Tua': baseColor = Colors.blue.shade900; break;
                        case 'Nila': baseColor = Colors.indigo; break;
                        case 'Ungu': baseColor = Colors.purple; break;
                        default: baseColor = Colors.grey;
                      }
                      return FilterChip(
                        label: Text(color, style: TextStyle(color: isSelected ? Colors.white : baseColor)),
                        selected: isSelected,
                        selectedColor: baseColor,
                        checkmarkColor: Colors.white,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedColors.add(color);
                            } else {
                              _selectedColors.remove(color);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text('Ukuran:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Wrap(
                    spacing: 8,
                    children: _availableSizes.map((size) {
                      final isSelected = _selectedSizes.contains(size);
                      return FilterChip(
                        label: Text(size),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedSizes.add(size);
                            } else {
                              _selectedSizes.remove(size);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // PENGIRIMAN
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Pengiriman'),
                  _buildTextField('Berat (Gram)', _weightController, isNumber: true, isRequired: true),
                  const Text('Ukuran Paket (cm) - Opsional', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Lebar', _widthController, isNumber: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Panjang', _lengthController, isNumber: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Tinggi', _heightController, isNumber: true)),
                    ],
                  ),
                ],
              ),
            ),

            // LAINNYA
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Lainnya'),
                  DropdownButtonFormField<String>(
                    initialValue: _condition,
                    decoration: const InputDecoration(labelText: 'Kondisi', border: OutlineInputBorder()),
                    items: ['Baru', 'Pernah Dipakai']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _condition = v!),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Pre-Order'),
                    subtitle: const Text('Kirim pesanan dalam waktu lebih lama'),
                    contentPadding: EdgeInsets.zero,
                    value: _isPreorder,
                    onChanged: (val) => setState(() => _isPreorder = val),
                  ),
                  if (_isPreorder)
                    _buildTextField('Dikirim dalam (Hari)', _preorderDaysController, isNumber: true, isRequired: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
