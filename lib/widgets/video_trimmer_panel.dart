import 'dart:math' as math;

import 'package:flutter/material.dart';

class VideoTrimmerPanel extends StatelessWidget {
  final double durationSeconds;
  final double maxClipSeconds;
  final double minClipSeconds;
  final double trimStart;
  final double trimEnd;
  final double currentPositionSeconds;
  final bool isPlaying;
  final ValueChanged<double> onSeekTo;
  final void Function(double start, double end) onTrimChanged;
  final VoidCallback onTogglePreview;

  const VideoTrimmerPanel({
    super.key,
    required this.durationSeconds,
    this.maxClipSeconds = 90.0,
    this.minClipSeconds = 1.0,
    required this.trimStart,
    required this.trimEnd,
    required this.currentPositionSeconds,
    required this.isPlaying,
    required this.onSeekTo,
    required this.onTrimChanged,
    required this.onTogglePreview,
  });

  String _formatClock(double seconds) {
    final safe = math.max(0, seconds.floor());
    final m = safe ~/ 60;
    final s = safe % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatBadge(double seconds) {
    final safe = math.max(0, seconds.round());
    final m = safe ~/ 60;
    final s = safe % 60;
    if (m > 0 && s > 0) return '${m}m ${s}d';
    if (m > 0) return '$m menit';
    return '$s detik';
  }

  double _round1(double v) => (v * 10).roundToDouble() / 10;

  @override
  Widget build(BuildContext context) {
    if (durationSeconds <= 0) return const SizedBox.shrink();

    const primaryColor = Color(0xFF0F3460);
    final effectiveMin = math.min(
      minClipSeconds,
      math.max(0.5, durationSeconds),
    );
    final maxAllowed = math.min(maxClipSeconds, durationSeconds);
    final needsTrim = durationSeconds > maxClipSeconds;
    final clipLen = math.max(0.0, trimEnd - trimStart);
    final windowLen = clipLen > 0
        ? math.min(maxAllowed, math.max(effectiveMin, clipLen))
        : maxAllowed;
    final maxWindowStart = math.max(0.0, durationSeconds - windowLen);

    void handleStartChange(double rawStart) {
      final maxStart = math.max(0.0, durationSeconds - effectiveMin);
      final nextStart = rawStart.clamp(0.0, maxStart);
      var nextEnd = trimEnd;
      if (nextEnd - nextStart > maxAllowed) {
        nextEnd = math.min(durationSeconds, nextStart + maxAllowed);
      }
      if (nextEnd - nextStart < effectiveMin) {
        nextEnd = math.min(durationSeconds, nextStart + effectiveMin);
      }
      final s = _round1(nextStart);
      final e = _round1(nextEnd);
      onTrimChanged(s, e);
      onSeekTo(s);
    }

    void handleEndChange(double rawEnd) {
      final minEnd = math.min(durationSeconds, effectiveMin);
      final nextEnd = rawEnd.clamp(minEnd, durationSeconds);
      var nextStart = trimStart;
      if (nextEnd - nextStart > maxAllowed) {
        nextStart = math.max(0.0, nextEnd - maxAllowed);
      }
      if (nextEnd - nextStart < effectiveMin) {
        nextStart = math.max(0.0, nextEnd - effectiveMin);
      }
      final s = _round1(nextStart);
      final e = _round1(nextEnd);
      onTrimChanged(s, e);
      onSeekTo(math.max(s, e - 0.15));
    }

    void handleWindowSlide(double rawStart) {
      final nextStart = rawStart.clamp(0.0, maxWindowStart);
      final nextEnd = math.min(durationSeconds, nextStart + windowLen);
      final s = _round1(nextStart);
      final e = _round1(nextEnd);
      onTrimChanged(s, e);
      onSeekTo(s);
    }

    void jumpPreset(String mode) {
      final len = math.min(maxClipSeconds, durationSeconds);
      double nextStart = 0;
      if (mode == 'middle') {
        nextStart = math.max(0.0, (durationSeconds - len) / 2);
      } else if (mode == 'end') {
        nextStart = math.max(0.0, durationSeconds - len);
      }
      final nextEnd = math.min(durationSeconds, nextStart + len);
      final s = _round1(nextStart);
      final e = _round1(nextEnd);
      onTrimChanged(s, e);
      onSeekTo(s);
    }

    final leftRatio = (trimStart / durationSeconds).clamp(0.0, 1.0);
    final widthRatio = ((trimEnd - trimStart) / durationSeconds).clamp(
      0.0,
      1.0 - leftRatio,
    );
    final playRatio = (currentPositionSeconds / durationSeconds).clamp(
      0.0,
      1.0,
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0DCEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.content_cut, size: 16, color: primaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pilih Bagian Video (Maks ${_formatBadge(maxClipSeconds)})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: primaryColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_formatClock(trimStart)} - ${_formatClock(trimEnd)} (${_formatBadge(clipLen)})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          if (needsTrim) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Text(
                'Video berdurasi ${_formatBadge(durationSeconds)} (lebih dari 1,5 menit). Geser posisi awal/akhir di bawah untuk memilih bagian berdurasi maks 90 detik.',
                style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Visual timeline bar
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Container(
                height: 22,
                width: w,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBE4F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: leftRatio * w,
                      width: math.max(4.0, widthRatio * w),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: primaryColor, width: 1.5),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (playRatio * w - 1).clamp(0.0, math.max(0.0, w - 2)),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.redAccent),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '0:00',
                style: TextStyle(fontSize: 10.5, color: Colors.black54),
              ),
              Text(
                'Posisi: ${_formatClock(currentPositionSeconds)}',
                style: const TextStyle(fontSize: 10.5, color: Colors.black54),
              ),
              Text(
                _formatClock(durationSeconds),
                style: const TextStyle(fontSize: 10.5, color: Colors.black54),
              ),
            ],
          ),

          if (maxWindowStart > 0.2) ...[
            const SizedBox(height: 8),
            Text(
              'Geser posisi potongan (${_formatBadge(windowLen)}): ${_formatClock(trimStart)} - ${_formatClock(trimEnd)}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: trimStart.clamp(0.0, maxWindowStart),
                min: 0.0,
                max: maxWindowStart,
                activeColor: primaryColor,
                onChanged: handleWindowSlide,
              ),
            ),
          ],

          const SizedBox(height: 4),
          _buildPointSlider(
            context: context,
            label: 'Awal: ${_formatClock(trimStart)}',
            value: trimStart.clamp(0.0, durationSeconds),
            max: durationSeconds,
            activeColor: Colors.teal,
            onChanged: handleStartChange,
            onMinus1: () => handleStartChange(trimStart - 1),
            onPlus1: () => handleStartChange(trimStart + 1),
          ),
          _buildPointSlider(
            context: context,
            label: 'Akhir: ${_formatClock(trimEnd)}',
            value: trimEnd.clamp(0.0, durationSeconds),
            max: durationSeconds,
            activeColor: Colors.deepOrange,
            onChanged: handleEndChange,
            onMinus1: () => handleEndChange(trimEnd - 1),
            onPlus1: () => handleEndChange(trimEnd + 1),
          ),

          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: onTogglePreview,
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(
                  isPlaying ? 'Pause' : 'Preview Potongan',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              _presetBtn('Awal', () => jumpPreset('start')),
              _presetBtn('Tengah', () => jumpPreset('middle')),
              _presetBtn('Akhir', () => jumpPreset('end')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPointSlider({
    required BuildContext context,
    required String label,
    required double value,
    required double max,
    required Color activeColor,
    required ValueChanged<double> onChanged,
    required VoidCallback onMinus1,
    required VoidCallback onPlus1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            _stepBtn('-1d', onMinus1),
            const SizedBox(width: 6),
            _stepBtn('+1d', onPlus1),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            min: 0.0,
            max: math.max(0.5, max),
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black26),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _presetBtn(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: Color(0xFFB7C7DC)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }
}

