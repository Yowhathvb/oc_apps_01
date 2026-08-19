import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MentionInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isSending;
  final VoidCallback onSend;
  final FocusNode? focusNode;
  final int maxLines;

  const MentionInput({
    super.key,
    required this.controller,
    required this.hintText,
    required this.isSending,
    required this.onSend,
    this.focusNode,
    this.maxLines = 1,
  });

  @override
  State<MentionInput> createState() => _MentionInputState();
}

class _MentionInputState extends State<MentionInput> {
  OverlayEntry? _overlayEntry;
  List<dynamic> _suggestions = [];
  bool _isSearching = false;
  String _currentQuery = '';
  Timer? _debounce;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (selection.baseOffset == -1) {
      _removeOverlay();
      return;
    }

    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final mentionIndex = textBeforeCursor.lastIndexOf('@');

    if (mentionIndex != -1) {
      final textAfterAt = textBeforeCursor.substring(mentionIndex + 1);
      // Check if there is any space after @
      if (!textAfterAt.contains(' ')) {
        _currentQuery = textAfterAt;
        _searchUsers(_currentQuery);
        return;
      }
    }
    _removeOverlay();
  }

  Future<void> _searchUsers(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _isSearching = true;
      });
      _showOverlay(); // show loading state

      final res = await ApiService.searchUsers(query);
      if (mounted && _currentQuery == query) {
        setState(() {
          _isSearching = false;
          if (res['success'] == true) {
            _suggestions = res['data'];
            if (_suggestions.isNotEmpty) {
              _showOverlay();
            } else {
              _removeOverlay();
            }
          } else {
            _removeOverlay();
          }
        });
      }
    });
  }

  void _showOverlay() {
    _removeOverlay();

    if (!mounted) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, -(_suggestions.length * 56.0).clamp(0.0, 200.0) - 10), // Show above the text field
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          final user = _suggestions[index];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.grey[300],
                              backgroundImage: user['avatar'] != null ? NetworkImage(ApiService.getServerUrl(user['avatar'])) : null,
                              child: user['avatar'] == null ? Text(user['name'].toString().substring(0, 1).toUpperCase()) : null,
                            ),
                            title: Text(user['username'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(user['name'], style: const TextStyle(fontSize: 12)),
                            onTap: () {
                              _insertMention(user['username']);
                            },
                          );
                        },
                      ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _insertMention(String username) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final mentionIndex = textBeforeCursor.lastIndexOf('@');

    final newText = text.substring(0, mentionIndex) + '@ ' + text.substring(selection.baseOffset);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: mentionIndex + username.length + 2),
    );
    _removeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        maxLines: widget.maxLines,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          suffixIcon: widget.isSending
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF0F3460)),
                  onPressed: widget.onSend,
                ),
        ),
      ),
    );
  }
}
