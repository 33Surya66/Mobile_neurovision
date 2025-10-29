import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/landmark_notifier.dart' as ln;
import 'api_service.dart';

class FaceMetrics {
  final int landmarkCount;
  final double faceAreaPercent;
  final double attentionPercent;
  final double drowsinessPercent;
  final double ear; // estimated eye aspect ratio-like value
  final int blinkCount;
  final double blinkRate; // blinks per minute
  final double pupilSize; // 0.0 to 1.0 (relative size)
  final double cognitiveLoad; // 0.0 to 100.0
  final double gazeStability; // 0.0 to 100.0 (higher is more stable)
  final double facialSymmetry; // 0.0 to 100.0 (higher is more symmetrical)

  const FaceMetrics({
    required this.landmarkCount,
    required this.faceAreaPercent,
    required this.attentionPercent,
    required this.drowsinessPercent,
    required this.ear,
    required this.blinkCount,
    this.blinkRate = 0.0,
    this.pupilSize = 0.0,
    this.cognitiveLoad = 0.0,
    this.gazeStability = 0.0,
    this.facialSymmetry = 0.0,
  });
}

class MetricsService {
  static final ValueNotifier<FaceMetrics> metricsNotifier = ValueNotifier(const FaceMetrics(
    landmarkCount: 0,
    faceAreaPercent: 0.0,
    attentionPercent: 0.0,
    drowsinessPercent: 0.0,
    ear: 0.0,
    blinkCount: 0,
    blinkRate: 0.0,
    pupilSize: 0.0,
    cognitiveLoad: 0.0,
    gazeStability: 0.0,
    facialSymmetry: 0.0,
  ));

  static final List<double> _earHistory = [];
  static int _blinkCount = 0;
  static bool _blinkInProgress = false;
  // short rolling histories (for dashboard sparklines)
  static final List<double> _attentionHistory = [];
  static final List<double> _drowsinessHistory = [];
  static final List<double> _blinkHistory = [];
  static final List<double> _cognitiveLoadHistory = [];
  static final List<double> _gazeStabilityHistory = [];
  static final List<double> _blinkRateHistory = [];

  // Notifiers for time series data
  static final ValueNotifier<List<double>> attentionSeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> drowsinessSeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> blinkSeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> cognitiveLoadSeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> gazeStabilitySeriesNotifier = ValueNotifier<List<double>>(<double>[]);
  static final ValueNotifier<List<double>> blinkRateSeriesNotifier = ValueNotifier<List<double>>(<double>[]);

  // For blink rate calculation
  static final List<DateTime> _blinkTimes = [];
  static double? _lastBlinkRate;
  static const int _blinkWindowMinutes = 1; // Calculate blink rate over this window

  // For gaze stability calculation
  static final List<Offset> _recentGazePositions = [];
  static const int _maxGazeSamples = 30; // Number of recent gaze positions to track

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
      metricsNotifier.value = FaceMetrics(
        landmarkCount: 0,
        faceAreaPercent: 0.0,
        attentionPercent: 0.0,
        drowsinessPercent: 0.0,
        ear: 0.0,
        blinkCount: _blinkCount,
        blinkRate: _calculateBlinkRate(),
        pupilSize: 0.0,
        cognitiveLoad: 0.0,
        gazeStability: 0.0,
        facialSymmetry: 0.0,
      );
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

    // Calculate additional metrics
    final double blinkRate = _calculateBlinkRate();
    final double cognitiveLoad = _calculateCognitiveLoad(ear);
    final double gazeStability = _calculateGazeStability(pts);
    final double facialSymmetry = _calculateFacialSymmetry(pts);

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
      _blinkTimes.add(DateTime.now());
      
      // Remove the oldest blink time if we have too many
      if (_blinkTimes.length > 100) { // Keep a reasonable limit
        _blinkTimes.removeAt(0);
      }
    }

    // Update metrics
    metricsNotifier.value = FaceMetrics(
      landmarkCount: pts.length,
      faceAreaPercent: double.parse(percent.toStringAsFixed(1)),
      attentionPercent: double.parse(attention.clamp(0.0, 100.0).toStringAsFixed(1)),
      drowsinessPercent: double.parse(drowsiness.toStringAsFixed(1)),
      ear: double.parse(avgEar.toStringAsFixed(3)),
      blinkCount: _blinkCount,
      blinkRate: blinkRate,
      pupilSize: _estimatePupilSize(pts),
      cognitiveLoad: cognitiveLoad,
      gazeStability: gazeStability,
      facialSymmetry: facialSymmetry,
    );

    // Send metrics to backend (non-blocking)
    try {
      _maybeSendMetrics(metricsNotifier.value);
    } catch (_) {}

    // Update rolling histories for sparklines
    _updateHistories(cognitiveLoad, gazeStability, blinkRate);

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

  static void _maybeSendMetrics(FaceMetrics m) {
    // Build a concise metrics payload (six dashboard metrics)
    final payload = {
      'landmarkCount': m.landmarkCount,
      'faceAreaPercent': m.faceAreaPercent,
      'attentionPercent': m.attentionPercent,
      'drowsinessPercent': m.drowsinessPercent,
      'ear': m.ear,
      'blinkCount': m.blinkCount,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Fire-and-forget; ApiService handles session checks
    ApiService.postMetrics(payload).then((ok) {}).catchError((_) {});
  }

  static double _calculateDrowsiness(double ear) {
    // Simple drowsiness calculation (inverse of attention)
    return 100.0 - _calculateAttention(ear);
  }

  static double _calculateCognitiveLoad(double ear) {
    // Cognitive load is estimated based on pupil size and blink rate
    // This is a simplified estimation
    final double baseLoad = (1.0 - (ear / 0.3)).clamp(0.0, 1.0) * 100.0;
    final double blinkContribution = (_blinkCount % 10) * 2.0; // Add some variation based on blink count
    return (baseLoad * 0.7 + blinkContribution * 0.3).clamp(0.0, 100.0);
  }

  static double _calculateGazeStability(List<Offset> pts) {
    if (pts.length < 2) return 0.0;

    // Add current gaze position (average of both eyes)
    final leftEye = _getLandmark(pts, 0); // Left eye center
    final rightEye = _getLandmark(pts, 1); // Right eye center
    if (leftEye == null || rightEye == null) return 0.0;

    final gazePoint = Offset(
      (leftEye.dx + rightEye.dx) / 2,
      (leftEye.dy + rightEye.dy) / 2,
    );

    _recentGazePositions.add(gazePoint);
    if (_recentGazePositions.length > _maxGazeSamples) {
      _recentGazePositions.removeAt(0);
    }

    // Calculate gaze stability based on variance of recent gaze positions
    if (_recentGazePositions.length < 5) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < _recentGazePositions.length; i++) {
      totalDistance += (_recentGazePositions[i] - _recentGazePositions[i - 1]).distance;
    }

    // Convert to stability score (0-100)
    final double avgDistance = totalDistance / (_recentGazePositions.length - 1);
    return (100.0 - (avgDistance * 1000).clamp(0.0, 100.0));
  }

  static double _calculateBlinkRate() {
    final now = DateTime.now();
    const int minSamples = 3; // Minimum number of blinks needed for accurate rate
    const int maxWindowSeconds = 30; // Maximum window to look back for blinks
    
    // Remove blinks older than our time window
    _blinkTimes.removeWhere((time) => now.difference(time).inSeconds > maxWindowSeconds);
    
    // Need at least 3 blinks to calculate a meaningful rate
    if (_blinkTimes.length < minSamples) return 0.0;
    
    // Calculate average time between blinks in seconds
    double totalIntervals = 0.0;
    int validIntervals = 0;
    
    for (int i = 1; i < _blinkTimes.length; i++) {
      final interval = _blinkTimes[i].difference(_blinkTimes[i-1]).inMilliseconds / 1000.0;
      
      // Only consider intervals between 100ms and 5 seconds (to filter out noise and long pauses)
      if (interval > 0.1 && interval < 5.0) {
        totalIntervals += interval;
        validIntervals++;
      }
    }
    
    // If we don't have enough valid intervals, return 0
    if (validIntervals < 2) return 0.0;
    
    // Calculate average interval in seconds, then convert to blinks per minute
    final double avgInterval = totalIntervals / validIntervals;
    final double blinksPerMinute = 60.0 / avgInterval;
    
    // Apply smoothing to prevent rapid fluctuations
    if (_lastBlinkRate != null) {
      return (_lastBlinkRate! * 0.7) + (blinksPerMinute * 0.3);
    }
    
    _lastBlinkRate = blinksPerMinute;
    return blinksPerMinute;
  }

  static double _estimatePupilSize(List<Offset> pts) {
    // This is a simplified estimation - in a real app, you'd use more sophisticated methods
    if (pts.length < 4) return 0.0;

    // Get eye landmarks (simplified)
    final leftPupil = _getLandmark(pts, 2);
    final rightPupil = _getLandmark(pts, 3);

    if (leftPupil == null || rightPupil == null) return 0.0;

    // Calculate distance between pupils as a reference
    final double interPupilDistance = (leftPupil - rightPupil).distance;

    // This is a very rough estimation - in reality, you'd need to measure the actual pupil size
    // from the eye region of the face
    return (interPupilDistance * 0.2).clamp(0.0, 1.0);
  }

  static double _calculateFacialSymmetry(List<Offset> pts) {
    if (pts.length < 10) return 0.0;

    // Calculate symmetry between left and right facial features
    // This is a simplified version - in reality, you'd want to compare more points
    final leftEye = _getLandmark(pts, 0);
    final rightEye = _getLandmark(pts, 1);
    final nose = _getLandmark(pts, 4);

    if (leftEye == null || rightEye == null || nose == null) return 0.0;

    // Calculate distances from nose to each eye
    final double leftDist = (leftEye - nose).distance;
    final double rightDist = (rightEye - nose).distance;

    // Calculate symmetry score (0-100)
    final double diff = (leftDist - rightDist).abs();
    final double maxDiff = (leftDist + rightDist) / 2 * 0.5; // Allow 50% difference max
    return 100.0 * (1.0 - (diff / maxDiff).clamp(0.0, 1.0));
  }

  static Offset? _getLandmark(List<Offset> pts, int index) {
    return index < pts.length ? pts[index] : null;
  }

  static double _calculateAttention(double ear) {
    // Simple attention calculation based on EAR (Eye Aspect Ratio)
    // Higher EAR means more open eyes (more attentive)
    return (ear / 0.3 * 100).clamp(0.0, 100.0);
  }

  static void _updateHistories(double cognitiveLoad, double gazeStability, double blinkRate) {
    _attentionHistory.add(metricsNotifier.value.attentionPercent);
    _drowsinessHistory.add(metricsNotifier.value.drowsinessPercent);
    _blinkHistory.add(_blinkCount.toDouble());

    // Add new metrics to their respective histories
    _cognitiveLoadHistory.add(cognitiveLoad);
    _gazeStabilityHistory.add(gazeStability);
    _blinkRateHistory.add(blinkRate);

    // Keep only last 50 data points
    const int maxPoints = 50;
    if (_attentionHistory.length > maxPoints) _attentionHistory.removeAt(0);
    if (_drowsinessHistory.length > maxPoints) _drowsinessHistory.removeAt(0);
    if (_blinkHistory.length > maxPoints) _blinkHistory.removeAt(0);
    if (_cognitiveLoadHistory.length > maxPoints) _cognitiveLoadHistory.removeAt(0);
    if (_gazeStabilityHistory.length > maxPoints) _gazeStabilityHistory.removeAt(0);
    if (_blinkRateHistory.length > maxPoints) _blinkRateHistory.removeAt(0);

    // Update notifiers
    attentionSeriesNotifier.value = List.from(_attentionHistory);
    drowsinessSeriesNotifier.value = List.from(_drowsinessHistory);
    blinkSeriesNotifier.value = List.from(_blinkHistory);
    cognitiveLoadSeriesNotifier.value = List.from(_cognitiveLoadHistory);
    gazeStabilitySeriesNotifier.value = List.from(_gazeStabilityHistory);
    blinkRateSeriesNotifier.value = List.from(_blinkRateHistory);
  }
}
