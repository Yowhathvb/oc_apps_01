import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaPlayerControlsConfig {
  final bool showPlayPause;
  final bool showSeekBar;
  final bool showTime;
  final bool showVolume;
  final bool showSpeed;
  final bool showLoop;
  final bool showPip;
  final bool showFullscreen;
  final bool showDownload;
  final bool showFitToggle;
  final bool showStats;

  const MediaPlayerControlsConfig({
    this.showPlayPause = true,
    this.showSeekBar = true,
    this.showTime = true,
    this.showVolume = true,
    this.showSpeed = true,
    this.showLoop = true,
    this.showPip = true,
    this.showFullscreen = true,
    this.showDownload = true,
    this.showFitToggle = true,
    this.showStats = true,
  });

  static bool _toBool(dynamic val, bool fallback) {
    if (val is bool) return val;
    if (val == 'true' || val == '1' || val == 1) return true;
    if (val == 'false' || val == '0' || val == 0) return false;
    return fallback;
  }

  factory MediaPlayerControlsConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MediaPlayerControlsConfig();
    return MediaPlayerControlsConfig(
      showPlayPause: _toBool(json['showPlayPause'], true),
      showSeekBar: _toBool(json['showSeekBar'], true),
      showTime: _toBool(json['showTime'], true),
      showVolume: _toBool(json['showVolume'], true),
      showSpeed: _toBool(json['showSpeed'], true),
      showLoop: _toBool(json['showLoop'], true),
      showPip: _toBool(json['showPip'], true),
      showFullscreen: _toBool(json['showFullscreen'], true),
      showDownload: _toBool(json['showDownload'], true),
      showFitToggle: _toBool(json['showFitToggle'], true),
      showStats: _toBool(json['showStats'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'showPlayPause': showPlayPause,
        'showSeekBar': showSeekBar,
        'showTime': showTime,
        'showVolume': showVolume,
        'showSpeed': showSpeed,
        'showLoop': showLoop,
        'showPip': showPip,
        'showFullscreen': showFullscreen,
        'showDownload': showDownload,
        'showFitToggle': showFitToggle,
        'showStats': showStats,
      };

  MediaPlayerControlsConfig copyWith({
    bool? showPlayPause,
    bool? showSeekBar,
    bool? showTime,
    bool? showVolume,
    bool? showSpeed,
    bool? showLoop,
    bool? showPip,
    bool? showFullscreen,
    bool? showDownload,
    bool? showFitToggle,
    bool? showStats,
  }) {
    return MediaPlayerControlsConfig(
      showPlayPause: showPlayPause ?? this.showPlayPause,
      showSeekBar: showSeekBar ?? this.showSeekBar,
      showTime: showTime ?? this.showTime,
      showVolume: showVolume ?? this.showVolume,
      showSpeed: showSpeed ?? this.showSpeed,
      showLoop: showLoop ?? this.showLoop,
      showPip: showPip ?? this.showPip,
      showFullscreen: showFullscreen ?? this.showFullscreen,
      showDownload: showDownload ?? this.showDownload,
      showFitToggle: showFitToggle ?? this.showFitToggle,
      showStats: showStats ?? this.showStats,
    );
  }
}

class MediaViewSettings {
  static const String _storageKey = 'ourchat_media_view_settings';
  static const List<String> validLayouts = ['feed', 'tiktok', 'grid'];
  static const List<String> validFits = ['contain', 'cover', 'fill'];
  static const List<String> validRatios = ['auto', '9:16', '16:9', '4:5', '1:1'];
  static const List<String> validPreloads = ['none', 'metadata', 'auto'];
  static const List<double> validSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  final String layout; // 'feed' | 'tiktok' | 'grid'
  final String objectFit; // 'contain' | 'cover' | 'fill'
  final String aspectRatio; // 'auto' | '9:16' | '16:9' | '4:5' | '1:1'
  final int maxHeight; // 220..1200
  final bool autoplay;
  final bool muted;
  final bool loop;
  final String preload; // 'none' | 'metadata' | 'auto'
  final bool sequentialRender;
  final double defaultSpeed;
  final MediaPlayerControlsConfig controls;

  const MediaViewSettings({
    this.layout = 'feed',
    this.objectFit = 'contain',
    this.aspectRatio = 'auto',
    this.maxHeight = 600,
    this.autoplay = false,
    this.muted = true,
    this.loop = true,
    this.preload = 'metadata',
    this.sequentialRender = true,
    this.defaultSpeed = 1.0,
    this.controls = const MediaPlayerControlsConfig(),
  });

  static const MediaViewSettings defaults = MediaViewSettings();

  BoxFit get boxFit {
    switch (objectFit) {
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      default:
        return BoxFit.contain;
    }
  }

  double? resolveAspectRatio(double? videoRatio) {
    switch (aspectRatio) {
      case '9:16':
        return 9 / 16;
      case '16:9':
        return 16 / 9;
      case '4:5':
        return 4 / 5;
      case '1:1':
        return 1.0;
      case 'auto':
      default:
        if (videoRatio != null && videoRatio > 0) return videoRatio;
        return null;
    }
  }

  factory MediaViewSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;

    final layout = validLayouts.contains(json['layout'])
        ? json['layout'].toString()
        : defaults.layout;
    final objectFit = validFits.contains(json['objectFit'])
        ? json['objectFit'].toString()
        : defaults.objectFit;
    final aspectRatio = validRatios.contains(json['aspectRatio'])
        ? json['aspectRatio'].toString()
        : defaults.aspectRatio;
    final preload = validPreloads.contains(json['preload'])
        ? json['preload'].toString()
        : defaults.preload;

    final rawHeight = (json['maxHeight'] is num)
        ? (json['maxHeight'] as num).round()
        : int.tryParse(json['maxHeight']?.toString() ?? '') ?? defaults.maxHeight;
    final maxHeight = rawHeight.clamp(220, 1200);

    final rawSpeed = (json['defaultSpeed'] is num)
        ? (json['defaultSpeed'] as num).toDouble()
        : double.tryParse(json['defaultSpeed']?.toString() ?? '') ?? defaults.defaultSpeed;
    final defaultSpeed =
        validSpeeds.contains(rawSpeed) ? rawSpeed : defaults.defaultSpeed;

    final controlsMap = json['controls'] is Map<String, dynamic>
        ? json['controls'] as Map<String, dynamic>
        : (json['controls'] is Map
            ? Map<String, dynamic>.from(json['controls'] as Map)
            : null);

    return MediaViewSettings(
      layout: layout,
      objectFit: objectFit,
      aspectRatio: aspectRatio,
      maxHeight: maxHeight,
      autoplay: MediaPlayerControlsConfig._toBool(json['autoplay'], defaults.autoplay),
      muted: MediaPlayerControlsConfig._toBool(json['muted'], defaults.muted),
      loop: MediaPlayerControlsConfig._toBool(json['loop'], defaults.loop),
      preload: preload,
      sequentialRender: MediaPlayerControlsConfig._toBool(
          json['sequentialRender'], defaults.sequentialRender),
      defaultSpeed: defaultSpeed,
      controls: MediaPlayerControlsConfig.fromJson(controlsMap),
    );
  }

  Map<String, dynamic> toJson() => {
        'layout': layout,
        'objectFit': objectFit,
        'aspectRatio': aspectRatio,
        'maxHeight': maxHeight,
        'autoplay': autoplay,
        'muted': muted,
        'loop': loop,
        'preload': preload,
        'sequentialRender': sequentialRender,
        'defaultSpeed': defaultSpeed,
        'controls': controls.toJson(),
      };

  MediaViewSettings copyWith({
    String? layout,
    String? objectFit,
    String? aspectRatio,
    int? maxHeight,
    bool? autoplay,
    bool? muted,
    bool? loop,
    String? preload,
    bool? sequentialRender,
    double? defaultSpeed,
    MediaPlayerControlsConfig? controls,
  }) {
    return MediaViewSettings(
      layout: layout ?? this.layout,
      objectFit: objectFit ?? this.objectFit,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      maxHeight: maxHeight ?? this.maxHeight,
      autoplay: autoplay ?? this.autoplay,
      muted: muted ?? this.muted,
      loop: loop ?? this.loop,
      preload: preload ?? this.preload,
      sequentialRender: sequentialRender ?? this.sequentialRender,
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      controls: controls ?? this.controls,
    );
  }

  static Future<MediaViewSettings> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return defaults;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return MediaViewSettings.fromJson(decoded);
      }
    } catch (_) {
      // Ignore corrupt local settings
    }
    return defaults;
  }

  Future<void> saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(toJson()));
    } catch (_) {
      // Ignore storage error
    }
  }
}

