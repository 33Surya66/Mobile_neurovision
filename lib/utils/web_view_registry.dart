// This file is only used on web builds. It registers a platform view factory
// that creates a container <div> for the NeuroVision video+canvas so it can be
// embedded into the Flutter widget tree via `HtmlElementView`.
//
// NOTE: This file is conditionally imported only when `dart.library.html` is
// available (see the conditional import in `main.dart`).

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

void registerNeurovisionView() {
  // For now, we'll use a simpler approach without platform view registry
  // The web detection is handled directly in index.html
  // This function is kept for compatibility but does minimal work
  debugPrint('NeuroVision web view registration - using direct DOM approach');
}
