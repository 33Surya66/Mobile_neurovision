import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/landmark_notifier.dart' as ln;

class FaceMetrics {
  final int landmarkCount;
  final double faceAreaPercent;
  final double attentionPercent;
  final double drowsinessPercent;
  final double ear; // estimated eye aspect ratio-like value
  final int blinkCount;

  const FaceMetrics({
    required this.landmarkCount,
    required this.faceAreaPercent,
    required this.attentionPercent,
    required this.drowsinessPercent,
    required this.ear,
    required this.blinkCount,
  });
}

class MetricsService {
  static final ValueNotifier<FaceMetrics> metricsNotifier = ValueNotifier(const FaceMetrics(landmarkCount: 0, faceAreaPercent: 0.0, attentionPercent: 0.0, drowsinessPercent: 0.0, ear: 0.0, blinkCount: 0));

  static final List<double> _earHistory = [];
  static int _blinkCount = 0;
  static bool _blinkInProgress = false;
  // short rolling histories (for dashboard sparklines)
  static final List<double> _attentionHistory = [];
  static final List<double> _drowsinessHistory = [];
  static final List<double> _blinkHistory = [];

  static final ValueNotifier<List<double>> attentionSeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> drowsinessSeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> blinkSeriesNotifier = ValueNotifier<List<double>>(<double>[]);

  static StreamSubscription<List<Offset>>? _sub;

  static void start() {
    // listen to global landmarksNotifier
    _sub = ln.landmarksNotifier.addListener(() {
      final pts = ln.landmarksNotifier.value;
      _process(pts);
    }) as StreamSubscription<List<Offset>>?;
    // Note: ValueNotifier.addListener doesn't return a subscription; keep API simple and call process on demand elsewhere
  }

  /// Stop is a no-op for now
  static void stop() {
    // no-op
  }

  /// Process landmarks (normalized Offsets 0..1)
  static void processLandmarks(List<Offset> pts) {
    _process(pts);
  }

  static void _process(List<Offset> pts) {
    if (pts.isEmpty) {
      metricsNotifier.value = const FaceMetrics(landmarkCount: 0, faceAreaPercent: 0.0, attentionPercent: 0.0, drowsinessPercent: 0.0, ear: 0.0, blinkCount: 0);
      return;
    }

    // bounding box
    double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    final width = (maxX - minX).clamp(0.0001, 1.0);
    final height = (maxY - minY).clamp(0.0001, 1.0);
    final area = (width * height).clamp(0.0, 1.0);
    final percent = (area * 100.0);

    // attention (centeredness + size)
    final centroidX = (minX + maxX) / 2.0;
    final centeredFactor = (1.0 - (2 * (centroidX - 0.5).abs())).clamp(0.0, 1.0);
    final sizeFactor = area.clamp(0.0, 1.0);
    final attention = (centeredFactor * 0.6 + sizeFactor * 0.4) * 100.0;

    // crude EAR-like: take points in upper region (eyes) vs horizontal width
    final eyeTop = minY + height * 0.12;
    final eyeBottom = minY + height * 0.38;
    final eyePts = pts.where((p) => p.dy >= eyeTop && p.dy <= eyeBottom).toList();
    double ear = 0.0;
    if (eyePts.length >= 6) {
      // estimate vertical spread vs horizontal spread
      double minEx = double.infinity, maxEx = -double.infinity, minEy = double.infinity, maxEy = -double.infinity;
      for (final p in eyePts) {
        if (p.dx < minEx) minEx = p.dx;
        if (p.dx > maxEx) maxEx = p.dx;
        if (p.dy < minEy) minEy = p.dy;
        if (p.dy > maxEy) maxEy = p.dy;
      }
      final h = (maxEy - minEy).clamp(0.0001, 1.0);
      final w = (maxEx - minEx).clamp(0.0001, 1.0);
      ear = (h / w);
    }

    // smoothing
    _earHistory.add(ear);
    if (_earHistory.length > 30) _earHistory.removeAt(0);
    final avgEar = _earHistory.isEmpty ? 0.0 : _earHistory.reduce((a, b) => a + b) / _earHistory.length;

    // drowsiness mapping (lower ear => more drowsy)
    final normalized = ((0.28 - avgEar) / 0.13).clamp(0.0, 1.0);
    final drowsiness = normalized * 100.0;

    // blink detection (threshold heuristic)
    final blinkThresh = 0.20;
    if (!_blinkInProgress && avgEar > 0 && avgEar < blinkThresh) {
      _blinkInProgress = true;
    }
    if (_blinkInProgress && avgEar >= blinkThresh) {
      _blinkInProgress = false;
      _blinkCount += 1;
    }

    metricsNotifier.value = FaceMetrics(
      landmarkCount: pts.length,
      faceAreaPercent: double.parse(percent.toStringAsFixed(1)),
      attentionPercent: double.parse(attention.clamp(0.0, 100.0).toStringAsFixed(1)),
      drowsinessPercent: double.parse(drowsiness.toStringAsFixed(1)),
      ear: double.parse(avgEar.toStringAsFixed(3)),
      blinkCount: _blinkCount,
    );

    // append series (keep fixed length)
    const maxLen = 300; // e.g., ~5 minutes at 1s
    _attentionHistory.add(attention);
    if (_attentionHistory.length > maxLen) _attentionHistory.removeAt(0);
    _drowsinessHistory.add(drowsiness);
    if (_drowsinessHistory.length > maxLen) _drowsinessHistory.removeAt(0);
    _blinkHistory.add(_blinkCount.toDouble());
    if (_blinkHistory.length > maxLen) _blinkHistory.removeAt(0);

    attentionSeriesNotifier.value = List<double>.from(_attentionHistory);
    drowsinessSeriesNotifier.value = List<double>.from(_drowsinessHistory);
    blinkSeriesNotifier.value = List<double>.from(_blinkHistory);
  }
}

