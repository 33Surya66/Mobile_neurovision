// Web-only implementation to register a platform view factory for the DOM container
// ignore_for_file: avoid_web_libraries_in_flutter, undefined_prefixed_name

import 'dart:html' as html;
import 'dart:js_util' as js_util;

void importWebViewFactory() {
  final container = html.document.getElementById('neurovision-webcam') ?? html.DivElement()..id = 'neurovision-webcam';
  try {
    final registry = js_util.getProperty(js_util.globalThis, 'platformViewRegistry');
    if (registry != null) {
      js_util.callMethod(registry, 'registerViewFactory', [
        'neurovision-webcam',
        js_util.allowInterop((int viewId) => container)
      ]);
    }
  } catch (e) {
    // ignore: avoid_print
    print('platform view registry register error: $e');
  }
}
