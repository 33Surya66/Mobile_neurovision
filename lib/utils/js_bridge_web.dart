import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../utils/landmark_notifier.dart' as ln;

typedef LandmarkCallback = void Function(List<Map<String, double>> points);

html.EventListener? _listener;

void addLandmarkListener(LandmarkCallback cb) {
  removeLandmarkListener();
  _listener = (event) {
    try {
      final detail = (event as html.CustomEvent).detail;
      final List<Map<String, double>> pts = [];
      if (detail is List) {
        // Two supported shapes:
        // 1) List of numbers: [x0,y0,x1,y1,...] (flattened normalized coords)
        // 2) List of maps or list of lists: [{x:..,y:..}, ...] or [[x,y], ...]
        if (detail.isNotEmpty && detail.first is num) {
          // flattened numeric array
          for (var i = 0; i + 1 < detail.length; i += 2) {
            final x = (detail[i] ?? 0).toDouble();
            final y = (detail[i + 1] ?? 0).toDouble();
            pts.add({'x': x, 'y': y});
          }
          // Notify shared ValueNotifier for Flutter overlay painting
          // Use scheduleMicrotask to avoid re-entrancy in some browsers
          scheduleMicrotask(() => ln.notifyLandmarksFromFlatList(detail));
        } else {
          for (var p in detail) {
            if (p is Map) {
              final x = (p['x'] ?? 0).toDouble();
              final y = (p['y'] ?? 0).toDouble();
              pts.add({'x': x, 'y': y});
            } else if (p is List && p.length >= 2) {
              pts.add({'x': (p[0]).toDouble(), 'y': (p[1]).toDouble()});
            }
          }
          scheduleMicrotask(() => ln.notifyLandmarksFromMaps(pts));
        }
      }
      // Call the legacy callback as well for existing metric code
      cb(pts);
    } catch (e) {
      // ignore
    }
  };
  html.window.addEventListener('neurovision_landmarks', _listener!);
}

void removeLandmarkListener() {
  if (_listener != null) {
    html.window.removeEventListener('neurovision_landmarks', _listener!);
    _listener = null;
  }
}
