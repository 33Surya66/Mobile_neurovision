// This file is only used on web builds. It registers a platform view factory
// that creates a container <div> for the NeuroVision video+canvas so it can be
// embedded into the Flutter widget tree via `HtmlElementView`.
//
// NOTE: This file is conditionally imported only when `dart.library.html` is
// available (see the conditional import in `main.dart`).

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// Import dart:ui without alias so we can reference platformViewRegistry directly.
// ignore: undefined_prefixed_name
import 'dart:ui';

void registerNeurovisionView() {
  // Register a view factory that provides the container element used by
  // `web/index.html`'s detection scripts (it looks up `#neurovision-webcam`).
  // ignore: undefined_prefixed_name
  platformViewRegistry.registerViewFactory('neurovision-video', (int viewId) {
    final container = html.DivElement()..id = 'neurovision-webcam';
    container.style.position = 'relative';
    container.style.width = '100%';
    container.style.height = '100%';
    container.style.overflow = 'hidden';
    container.style.borderRadius = '18px';
    container.style.pointerEvents = 'none';
    return container;
  });
}
