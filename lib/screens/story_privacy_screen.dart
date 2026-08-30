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
  
  // Stored selections (can be phone or username)
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _privacyType = prefs.getString('story_privacy_type') ?? 'kontak_saya';
      _exceptions = prefs.getStringList('story_privacy_exceptions') ?? [];
      _included = prefs.getStringList('story_privacy_included') ?? [];
      _closeFriends = prefs.getStringList('story_privacy_close_friends') ?? [];
    });

    final contactsData = await DatabaseHelper().getContacts();
    setState(() {
      _contacts = contactsData;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('story_privacy_type', _privacyType);
    await prefs.setStringList('story_privacy_exceptions', _exceptions);
    await prefs.setStringList('story_privacy_included', _included);
    await prefs.setStringList('story_privacy_close_friends', _closeFriends);
  }

  void _openContactPicker(String type) {
    List<String> currentSelection;
    if (type == 'kecuali') {
      currentSelection = List.from(_exceptions);
    } else if (type == 'hanya_bagikan') currentSelection = List.from(_included);
    else currentSelection = List.from(_closeFriends);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pilih Kontak', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (type == 'kecuali') {
                              _exceptions = currentSelection;
                            } else if (type == 'hanya_bagikan') _included = currentSelection;
                            else _closeFriends = currentSelection;
                            _privacyType = type;
                          });
                          _saveSettings();
                          Navigator.pop(context);
                        },
                        child: const Text('SELESAI'),
                      )
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _contacts.length,
                      itemBuilder: (context, index) {
                        final c = _contacts[index];
                        final identifier = c['username']?.toString() ?? c['phone']?.toString() ?? '';
                        final isSelected = currentSelection.contains(identifier);
                        
                        return CheckboxListTile(
                          title: Text(c['saved_name'] ?? identifier),
                          subtitle: Text(identifier),
                          value: isSelected,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                currentSelection.add(identifier);
                                if (c['phone'] != null && !currentSelection.contains(c['phone'])) {
                                  currentSelection.add(c['phone']);
                                }
                                if (c['username'] != null && !currentSelection.contains(c['username'])) {
                                  currentSelection.add(c['username']);
                                }
                              } else {
                                currentSelection.remove(identifier);
                                if (c['phone'] != null) currentSelection.remove(c['phone']);
                                if (c['username'] != null) currentSelection.remove(c['username']);
                              }
                            });
                          },
                        );
                      },
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privasi Status'),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Siapa yang dapat melihat pembaruan status saya?',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          RadioListTile<String>(
            title: const Text('Kontak saya'),
            value: 'kontak_saya',
            groupValue: _privacyType,
            onChanged: (val) {
              setState(() => _privacyType = val!);
              _saveSettings();
            },
          ),
          RadioListTile<String>(
            title: Text('Kontak saya kecuali... ${_exceptions.isNotEmpty && _privacyType == 'kecuali' ? '(${_exceptions.length ~/ 2} dikecualikan)' : ''}'),
            value: 'kecuali',
            groupValue: _privacyType,
            onChanged: (val) {
              _openContactPicker('kecuali');
            },
          ),
          RadioListTile<String>(
            title: Text('Hanya bagikan dengan... ${_included.isNotEmpty && _privacyType == 'hanya_bagikan' ? '(${_included.length ~/ 2} disertakan)' : ''}'),
            value: 'hanya_bagikan',
            groupValue: _privacyType,
            onChanged: (val) {
              _openContactPicker('hanya_bagikan');
            },
          ),
          RadioListTile<String>(
            title: Text('Teman dekat ${_closeFriends.isNotEmpty && _privacyType == 'teman_dekat' ? '(${_closeFriends.length ~/ 2} teman)' : ''}'),
            value: 'teman_dekat',
            groupValue: _privacyType,
            onChanged: (val) {
              _openContactPicker('teman_dekat');
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Perubahan pada pengaturan privasi Anda tidak akan memengaruhi pembaruan status yang sudah Anda kirim.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          )
        ],
      ),
    );
  }
}
