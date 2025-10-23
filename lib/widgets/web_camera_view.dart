// Conditional export: uses web implementation when compiled for web, stub otherwise.
export 'web_camera_view_stub.dart'
    if (dart.library.html) 'web_camera_view_web.dart';
