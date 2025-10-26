import 'package:flutter/material.dart';

/// Global notifier that holds the latest normalized landmark points
/// as a list of Offsets (x and y are normalized 0..1 relative to the video/frame).
final ValueNotifier<List<Offset>> landmarksNotifier = ValueNotifier<List<Offset>>(<Offset>[]);

/// Simple model holding ML Kit face-level metrics extracted from the last detection.
class MlFaceMetrics {
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;
  final double? headEulerAngleY; // yaw
  final double? headEulerAngleZ; // roll
  final int? trackingId;
  final DateTime timestamp;

  MlFaceMetrics({
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.trackingId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

final ValueNotifier<MlFaceMetrics?> mlFaceMetricsNotifier = ValueNotifier<MlFaceMetrics?>(null);

/// Helper to convert generic list of maps to Offset list and notify listeners.
void notifyLandmarksFromMaps(List<Map<String, double>> pts) {
  final out = <Offset>[];
  for (final p in pts) {
    final x = p['x'] ?? 0.0;
    final y = p['y'] ?? 0.0;
    out.add(Offset(x, y));
  }
  landmarksNotifier.value = out;
}

/// Helper to convert flattened numeric arrays [x0,y0,x1,y1,...]
void notifyLandmarksFromFlatList(List<dynamic> flat) {
  final out = <Offset>[];
  for (var i = 0; i + 1 < flat.length; i += 2) {
    final x = (flat[i] ?? 0).toDouble();
    final y = (flat[i + 1] ?? 0).toDouble();
    out.add(Offset(x, y));
  }
  landmarksNotifier.value = out;
}
