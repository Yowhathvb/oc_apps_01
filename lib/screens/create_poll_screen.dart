import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CreatePollScreen extends StatefulWidget {
  final String groupId;

  const CreatePollScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  static const Color _primaryColor = Color(0xFF0F3460);

  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [];
  final List<FocusNode> _focusNodes = [];

  bool _multipleAnswers = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Default 2 opsi awal
    _addNewOption();
    _addNewOption();

    _questionController.addListener(() => setState(() {}));
  }

  void _addNewOption() {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    controller.addListener(() {
      _checkAutoAddOption();
      setState(() {});
    });

    _optionControllers.add(controller);
    _focusNodes.add(focusNode);
  }

  void _checkAutoAddOption() {
    // Seperti WhatsApp: jika opsi terakhir mulai diisi dan jumlahnya < 12, tambah field baru otomatis
    if (_optionControllers.length < 12) {
      final last = _optionControllers.last.text.trim();
      if (last.isNotEmpty) {
        _addNewOption();
      }
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _focusNodes[index].dispose();
      _optionControllers.removeAt(index);
      _focusNodes.removeAt(index);
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _isValid {
    final q = _questionController.text.trim();
    if (q.isEmpty) return false;
    final validOptions = _optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    return validOptions.length >= 2;
  }

  Future<void> _submitPoll() async {
    if (!_isValid || _isLoading) return;

    final q = _questionController.text.trim();
    final validOptions = _optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

    setState(() => _isLoading = true);

    final cleanId = widget.groupId.replaceFirst('group_', '');
    final res = await ApiService.createGroupPoll(
      cleanId,
      question: q,
      options: validOptions,
      multipleAnswers: _multipleAnswers,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Gagal membuat polling'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Buat Polling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _isValid ? _submitPoll : null,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Kirim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white38,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // 1. Pertanyaan Polling
          const Text(
            'Pertanyaan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _questionController,
            maxLines: 3,
            minLines: 1,
            maxLength: 500,
            autofocus: true,
            style: const TextStyle(fontSize: 15, color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'Ketik pertanyaan polling...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFF7F9FC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primaryColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Opsi Pilihan
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Opsi Pilihan',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              Text(
                'Min. 2 opsi',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),

          ...List.generate(_optionControllers.length, (index) {
            final isLast = index == _optionControllers.length - 1;
            final canDelete = _optionControllers.length > 2 && !isLast;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[index],
                      focusNode: _focusNodes[index],
                      maxLength: 100,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: isLast ? '+ Tambah opsi' : 'Opsi ${index + 1}',
                        hintStyle: TextStyle(color: isLast ? _primaryColor.withOpacity(0.6) : Colors.grey.shade400),
                        filled: true,
                        fillColor: const Color(0xFFF7F9FC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _primaryColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                  if (canDelete) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                      tooltip: 'Hapus Opsi',
                      onPressed: () => _removeOption(index),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // 3. Pengaturan: Single vs Multiple Choice
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              activeColor: _primaryColor,
              title: const Text(
                'Izinkan beberapa jawaban',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
              ),
              subtitle: Text(
                _multipleAnswers
                    ? 'Anggota boleh memilih lebih dari satu opsi'
                    : 'Anggota hanya boleh memilih satu opsi',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: _multipleAnswers,
              onChanged: (val) {
                setState(() {
                  _multipleAnswers = val;
                });
              },
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
