import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/call_manager.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<dynamic> _callHistory = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCallHistory();
  }

  Future<void> _fetchCallHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final history = await DatabaseHelper().getCallHistory();
      setState(() {
        _callHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
      }
      return "${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return '';
    }
  }

  void _showNewCallBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseHelper().getContacts(),
          builder: (context, snapshot) {
            final contacts = snapshot.data ?? [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF0F3460),
                    child: Icon(Icons.dialpad, color: Colors.white),
                  ),
                  title: const Text('Nomor Baru', style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _showNewNumberDialog();
                  },
                ),
                const Divider(),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : contacts.isEmpty
                          ? const Center(child: Text('Belum ada kontak.'))
                          : ListView.builder(
                              itemCount: contacts.length,
                              itemBuilder: (context, index) {
                                final contact = contacts[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(
                                      contact['saved_name'].toString().substring(0, 1).toUpperCase(),
                                      style: const TextStyle(color: Color(0xFF0F3460)),
                                    ),
                                  ),
                                  title: Text(contact['saved_name']),
                                  subtitle: Text(contact['phone_number']),
                                  trailing: const Icon(Icons.call, color: Colors.green),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _startOutgoingCall(contact['phone_number'], contact['saved_name']);
                                  },
                                );
                              },
                            ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNewNumberDialog() {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Panggil Nomor Baru'),
          content: TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Nomor Telepon',
              hintText: '+62...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (phoneController.text.isNotEmpty) {
                  _startOutgoingCall(phoneController.text, 'Unknown');
                }
              },
              child: const Text('Panggil'),
            ),
          ],
        );
      },
    );
  }

  void _startOutgoingCall(String phone, String name) {
    CallManager.instance.startCall(phone, name, false);
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchCallHistory,
                        child: const Text('Coba Lagi'),
                      )
                    ],
                  ),
                )
              : _callHistory.isEmpty
                  ? const Center(child: Text('Belum ada riwayat panggilan.'))
                  : RefreshIndicator(
                      onRefresh: _fetchCallHistory,
                      child: ListView.builder(
                        itemCount: _callHistory.length,
                        itemBuilder: (context, index) {
                          final call = _callHistory[index];
                          final timeStr = _formatTime(call['timestamp']);
                          final isIncoming = call['direction'] == 'incoming';
                          final isMissed = call['status'] == 'missed' || (isIncoming && call['status'] == 'ringing');
                          
                          final otherName = call['other_name'];
                          final otherPhone = call['other_phone'];
                          final isVideo = call['type'] == 'video';

                          IconData statusIcon;
                          Color statusColor;

                          if (isMissed) {
                            statusIcon = isIncoming ? Icons.call_missed : Icons.call_missed_outgoing;
                            statusColor = Colors.red;
                          } else {
                            statusIcon = isIncoming ? Icons.call_received : Icons.call_made;
                            statusColor = isIncoming ? Colors.blue : Colors.green;
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                (otherName ?? '?').toString().substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              otherName ?? otherPhone ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isMissed ? Colors.red : Colors.black87,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (otherPhone != null && otherPhone != 'Unknown Number')
                                  Text(
                                    otherPhone,
                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  ),
                                Row(
                                  children: [
                                    Icon(statusIcon, size: 16, color: statusColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeStr,
                                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(isVideo ? Icons.videocam : Icons.phone, color: primaryColor),
                              onPressed: () {
                                if (otherPhone == null || otherPhone == 'Unknown Number') {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Nomor tidak valid')),
                                  );
                                  return;
                                }
                                CallManager.instance.startCall(otherPhone, otherName ?? otherPhone, isVideo);
                              },
                            ),
                            onTap: () {
                              // TODO: Tampilkan detail panggilan
                            },
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        onPressed: _showNewCallBottomSheet,
        child: const Icon(Icons.add_call),
      ),
    );
  }
}
