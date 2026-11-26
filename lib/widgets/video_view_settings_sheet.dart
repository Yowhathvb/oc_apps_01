import 'package:flutter/material.dart';
import '../models/media_view_settings.dart';
import '../services/api_service.dart';

class VideoViewSettingsSheet extends StatefulWidget {
  final MediaViewSettings initialSettings;
  final ValueChanged<MediaViewSettings> onChanged;

  const VideoViewSettingsSheet({
    super.key,
    required this.initialSettings,
    required this.onChanged,
  });

  @override
  State<VideoViewSettingsSheet> createState() => _VideoViewSettingsSheetState();
}

class _VideoViewSettingsSheetState extends State<VideoViewSettingsSheet> {
  late MediaViewSettings _draft;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
  }

  void _update(MediaViewSettings next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  Future<void> _saveToServer() async {
    setState(() => _isSaving = true);
    await _draft.saveLocal();
    final res = await ApiService.saveVideoViewSettings(_draft.toJson());
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] == true && res['viewConfig'] is Map) {
      final serverConfig = MediaViewSettings.fromJson(
        Map<String, dynamic>.from(res['viewConfig'] as Map),
      );
      await serverConfig.saveLocal();
      widget.onChanged(serverConfig);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengaturan view video disimpan ke server'),
          ),
        );
        Navigator.pop(context, serverConfig);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['message'] ?? 'Disimpan secara lokal (gagal sinkron ke server)',
          ),
        ),
      );
      Navigator.pop(context, _draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.94,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF102033),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pengaturan View & Kontrol Video',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Atur layout, rasio, render antrian 1-per-1, dan tombol player',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle('Layout Feed'),
                    _chipGroup(
                      options: const {
                        'feed': 'Feed',
                        'tiktok': 'Our Reels',
                        'grid': 'Grid',
                      },
                      selected: _draft.layout,
                      onSelect: (val) => _update(_draft.copyWith(layout: val)),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Object Fit'),
                    _chipGroup(
                      options: const {
                        'contain': 'Utuh (Contain)',
                        'cover': 'Penuh (Cover)',
                        'fill': 'Fill',
                      },
                      selected: _draft.objectFit,
                      onSelect: (val) =>
                          _update(_draft.copyWith(objectFit: val)),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Aspect Ratio'),
                    _chipGroup(
                      options: const {
                        'auto': 'Auto',
                        '9:16': '9:16',
                        '16:9': '16:9',
                        '4:5': '4:5',
                        '1:1': '1:1',
                      },
                      selected: _draft.aspectRatio,
                      onSelect: (val) =>
                          _update(_draft.copyWith(aspectRatio: val)),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle(
                      'Tinggi Maksimal Video Feed (${_draft.maxHeight} px)',
                    ),
                    Slider(
                      value: _draft.maxHeight.toDouble().clamp(220, 900),
                      min: 220,
                      max: 900,
                      divisions: 34,
                      activeColor: Colors.lightBlueAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (v) =>
                          _update(_draft.copyWith(maxHeight: v.round())),
                    ),
                    const SizedBox(height: 12),

                    _sectionTitle('Kecepatan Default'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: MediaViewSettings.validSpeeds.map((spd) {
                        final active = _draft.defaultSpeed == spd;
                        return ChoiceChip(
                          label: Text('${spd}x'),
                          selected: active,
                          selectedColor: primaryColor,
                          backgroundColor: const Color(0xFF1A2F4A),
                          labelStyle: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontWeight: active
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (_) =>
                              _update(_draft.copyWith(defaultSpeed: spd)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Perilaku Render & Playback'),
                    _switchTile(
                      title: 'Render Berurutan 1-per-1',
                      subtitle:
                          'Video dimuat berurutan satu per satu',
                      value: _draft.sequentialRender,
                      onChanged: (v) =>
                          _update(_draft.copyWith(sequentialRender: v)),
                    ),
                    _switchTile(
                      title: 'Autoplay saat terlihat',
                      value: _draft.autoplay,
                      onChanged: (v) => _update(_draft.copyWith(autoplay: v)),
                    ),
                    _switchTile(
                      title: 'Mute Default (Feed)',
                      value: _draft.muted,
                      onChanged: (v) => _update(_draft.copyWith(muted: v)),
                    ),
                    _switchTile(
                      title: 'Loop Video',
                      value: _draft.loop,
                      onChanged: (v) => _update(_draft.copyWith(loop: v)),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Tombol Kontrol Player'),
                    _switchTile(
                      title: 'Play / Pause',
                      value: _draft.controls.showPlayPause,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showPlayPause: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Seek Bar',
                      value: _draft.controls.showSeekBar,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showSeekBar: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Durasi & Waktu',
                      value: _draft.controls.showTime,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showTime: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Volume / Mute',
                      value: _draft.controls.showVolume,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showVolume: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Kecepatan (0.5x - 2x)',
                      value: _draft.controls.showSpeed,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showSpeed: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Tombol Loop',
                      value: _draft.controls.showLoop,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showLoop: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Switch Cover / Utuh',
                      value: _draft.controls.showFitToggle,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showFitToggle: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Mini Player (PiP)',
                      value: _draft.controls.showPip,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showPip: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Fullscreen',
                      value: _draft.controls.showFullscreen,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showFullscreen: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Unduh / Bagikan Video',
                      value: _draft.controls.showDownload,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showDownload: v),
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Info Video & Views',
                      value: _draft.controls.showStats,
                      onChanged: (v) => _update(
                        _draft.copyWith(
                          controls: _draft.controls.copyWith(showStats: v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Footer Actions
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => _update(MediaViewSettings.defaults),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        child: const Text('Reset Default'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveToServer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Simpan Pengaturan',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _chipGroup({
    required Map<String, String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((entry) {
        final isSelected = entry.key == selected;
        return ChoiceChip(
          label: Text(entry.value),
          selected: isSelected,
          selectedColor: const Color(0xFF0F3460),
          backgroundColor: const Color(0xFF1A2F4A),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => onSelect(entry.key),
        );
      }).toList(),
    );
  }

  Widget _switchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: Colors.lightBlueAccent,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            )
          : null,
      value: value,
      onChanged: onChanged,
    );
  }
}
