import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';

class StoryPrivacyScreen extends StatefulWidget {
  const StoryPrivacyScreen({super.key});

  @override
  State<StoryPrivacyScreen> createState() => _StoryPrivacyScreenState();
}

class _StoryPrivacyScreenState extends State<StoryPrivacyScreen> {
  String _privacyType = 'kontak_saya'; // 'kontak_saya', 'kecuali', 'hanya_bagikan', 'teman_dekat'
  List<Map<String, dynamic>> _contacts = [];
  
  // Stored selections (phone numbers)
  List<String> _exceptions = [];
  List<String> _included = [];
  List<String> _closeFriends = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // 1. Muat tipe privasi dari DB lokal SQLite (fallback ke SharedPreferences)
    String savedType = 'kontak_saya';
    try {
      savedType = await DatabaseHelper().getStoryPrivacyType();
    } catch (_) {}
    if (savedType == 'kontak_saya') {
      savedType = prefs.getString('story_privacy_type') ?? 'kontak_saya';
    }

    // 2. Muat data kontak masing-masing kategori dari DB lokal SQLite
    List<String> exceptions = [];
    List<String> included = [];
    List<String> closeFriends = [];

    try {
      exceptions = await DatabaseHelper().getStoryPrivacyCategory('kecuali');
      included = await DatabaseHelper().getStoryPrivacyCategory('hanya_bagikan');
      closeFriends = await DatabaseHelper().getStoryPrivacyCategory('teman_dekat');
    } catch (_) {}

    // Fallback jika DB SQLite kosong namun SharedPreferences ada data (migrasi data lama)
    if (exceptions.isEmpty) {
      exceptions = (prefs.getStringList('story_privacy_exceptions') ?? [])
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();
    }
    if (included.isEmpty) {
      included = (prefs.getStringList('story_privacy_included') ?? [])
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();
    }
    if (closeFriends.isEmpty) {
      closeFriends = (prefs.getStringList('story_privacy_close_friends') ?? [])
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();
    }

    final contactsData = await DatabaseHelper().getContacts();

    if (mounted) {
      setState(() {
        _privacyType = savedType;
        _exceptions = exceptions;
        _included = included;
        _closeFriends = closeFriends;
        _contacts = contactsData;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings({String? category}) async {
    // 1. Simpan ke Database Lokal SQLite
    try {
      await DatabaseHelper().saveStoryPrivacyType(_privacyType);
      if (category == null || category == 'kecuali') {
        await DatabaseHelper().saveStoryPrivacyCategory('kecuali', _exceptions);
      }
      if (category == null || category == 'hanya_bagikan') {
        await DatabaseHelper().saveStoryPrivacyCategory('hanya_bagikan', _included);
      }
      if (category == null || category == 'teman_dekat') {
        await DatabaseHelper().saveStoryPrivacyCategory('teman_dekat', _closeFriends);
      }
    } catch (e) {
      debugPrint('Error saving story privacy to local db: $e');
    }

    // 2. Simpan juga ke SharedPreferences untuk backward-compatibility
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('story_privacy_type', _privacyType);
    await prefs.setStringList('story_privacy_exceptions', _exceptions);
    await prefs.setStringList('story_privacy_included', _included);
    await prefs.setStringList('story_privacy_close_friends', _closeFriends);
  }

  void _selectPrivacyType(String type) {
    setState(() {
      _privacyType = type;
    });
    _saveSettings();
  }

  void _openContactPicker(String type) {
    List<String> currentSelection;
    String title;
    
    if (type == 'kecuali') {
      currentSelection = List.from(_exceptions);
      title = 'Kontak saya kecuali';
    } else if (type == 'hanya_bagikan') {
      currentSelection = List.from(_included);
      title = 'Hanya bagikan dengan';
    } else {
      currentSelection = List.from(_closeFriends);
      title = 'Teman dekat';
    }

    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final validContacts = _contacts.where((c) {
              final phone = (c['phone_number'] ?? '').toString().trim();
              return phone.isNotEmpty;
            }).toList();

            final filteredContacts = validContacts.where((c) {
              if (searchQuery.isEmpty) return true;
              final name = (c['saved_name'] ?? '').toString().toLowerCase();
              final phone = (c['phone_number'] ?? '').toString().toLowerCase();
              return name.contains(searchQuery) || phone.contains(searchQuery);
            }).toList();

            final bool isAllSelected = validContacts.isNotEmpty &&
                validContacts.every((c) {
                  final phone = (c['phone_number'] ?? '').toString().trim();
                  return currentSelection.contains(phone);
                });

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header bar
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F3460),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${currentSelection.length} dari ${validContacts.length} dipilih',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tombol Pilih Semua / Batalkan Semua dengan icon
                      IconButton(
                        icon: Icon(
                          isAllSelected ? Icons.deselect_outlined : Icons.select_all_outlined,
                          color: const Color(0xFF0F3460),
                        ),
                        tooltip: isAllSelected ? 'Batalkan Semua' : 'Pilih Semua',
                        onPressed: () {
                          setModalState(() {
                            if (isAllSelected) {
                              currentSelection.clear();
                            } else {
                              currentSelection = validContacts
                                  .map((c) => (c['phone_number'] ?? '').toString().trim())
                                  .where((p) => p.isNotEmpty)
                                  .toSet()
                                  .toList();
                            }
                          });
                        },
                      ),

                      // Tombol Selesai
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F3460),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: () {
                          setState(() {
                            if (type == 'kecuali') {
                              _exceptions = List.from(currentSelection);
                            } else if (type == 'hanya_bagikan') {
                              _included = List.from(currentSelection);
                            } else {
                              _closeFriends = List.from(currentSelection);
                            }
                            _privacyType = type;
                          });
                          _saveSettings(category: type);
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'SELESAI',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Kotak Pencarian Kontak
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Cari kontak...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val.trim().toLowerCase();
                      });
                    },
                  ),
                  const Divider(height: 16),

                  // Daftar Kontak
                  Expanded(
                    child: filteredContacts.isEmpty
                        ? Center(
                            child: Text(
                              searchQuery.isEmpty
                                  ? 'Tidak ada kontak tersimpan'
                                  : 'Kontak tidak ditemukan',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (context, index) {
                              final c = filteredContacts[index];
                              final phone = (c['phone_number'] ?? '').toString().trim();
                              final name = (c['saved_name'] ?? phone).toString().trim();
                              final isSelected = currentSelection.contains(phone);

                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: const Color(0xFF0F3460),
                                secondary: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? const Color(0xFF0F3460)
                                      : Colors.grey.shade200,
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : const Color(0xFF0F3460),
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  phone,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                                onChanged: (val) {
                                  // Seleksi 1 per 1 berdasarkan nomor HP kontak
                                  setModalState(() {
                                    if (val == true) {
                                      if (!currentSelection.contains(phone)) {
                                        currentSelection.add(phone);
                                      }
                                    } else {
                                      currentSelection.remove(phone);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategorySubtitle({
    required int count,
    required String labelSuffix,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count $labelSuffix',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Edit',
              style: TextStyle(
                color: Color(0xFF0F3460),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privasi Status'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Siapa yang dapat melihat pembaruan status saya?',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),

          // Opsi Privasi dengan RadioGroup
          RadioGroup<String>(
            groupValue: _privacyType,
            onChanged: (val) {
              if (val != null) _selectPrivacyType(val);
            },
            child: Column(
              children: [
                // 1. Kontak saya
                RadioListTile<String>(
                  activeColor: primaryColor,
                  title: const Text(
                    'Kontak saya',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  value: 'kontak_saya',
                ),

                // 2. Kontak saya kecuali...
                RadioListTile<String>(
                  activeColor: primaryColor,
                  title: const Text(
                    'Kontak saya kecuali...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  subtitle: _buildCategorySubtitle(
                    count: _exceptions.length,
                    labelSuffix: 'dikecualikan',
                    onTap: () => _openContactPicker('kecuali'),
                  ),
                  value: 'kecuali',
                ),

                // 3. Hanya bagikan dengan...
                RadioListTile<String>(
                  activeColor: primaryColor,
                  title: const Text(
                    'Hanya bagikan dengan...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  subtitle: _buildCategorySubtitle(
                    count: _included.length,
                    labelSuffix: 'disertakan',
                    onTap: () => _openContactPicker('hanya_bagikan'),
                  ),
                  value: 'hanya_bagikan',
                ),

                // 4. Teman dekat
                RadioListTile<String>(
                  activeColor: primaryColor,
                  title: const Text(
                    'Teman dekat',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  subtitle: _buildCategorySubtitle(
                    count: _closeFriends.length,
                    labelSuffix: 'disertakan',
                    onTap: () => _openContactPicker('teman_dekat'),
                  ),
                  value: 'teman_dekat',
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Perubahan pada pengaturan privasi Anda tidak akan memengaruhi pembaruan status yang sudah Anda kirim.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
