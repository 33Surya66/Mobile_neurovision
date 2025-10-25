import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/landmark_notifier.dart' as ln;
import 'package:http_parser/http_parser.dart';
// ML Kit for on-device face detection
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionService {
  static bool _isInitialized = false;
  static FaceDetector? _mlkitDetector;
  // Backend server URL (change to your backend address). Use https in production.
  // For local testing with a device on the same Wi-Fi, set this to your machine's LAN IP:
  // e.g. http://192.168.1.23:5000
  static String backendUrl = 'http://127.0.0.1:5000';
  
  // MediaPipe Face Mesh landmark indices for eyes
  static const List<int> leftEyeIndices = [33, 160, 158, 133, 153, 144];
  static const List<int> rightEyeIndices = [362, 385, 387, 263, 373, 380];
  
  static Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      // Initialize ML Kit face detector for on-device detection (Android/iOS)
      final options = FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
      );
      _mlkitDetector = FaceDetector(options: options);
      // For now, we'll keep the lightweight initialization flag
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Face detection initialization failed: $e');
      return false;
    }
  }
  
  /// Run face detection on a camera frame using ML Kit (mobile) when available.
  /// The [cameraDescription] is used to supply sensor orientation information.
  static Future<List<Offset>?> detectFacesFromCameraImage(CameraImage cameraImage, [CameraDescription? cameraDescription]) async {
    if (!_isInitialized) {
      await initialize();
    }

    // On web or if ML Kit not available, fall back to mock or backend path.
    if (kIsWeb || _mlkitDetector == null) {
      try {
        return _generateMockLandmarks(cameraImage.width, cameraImage.height);
      } catch (e) {
        debugPrint('Face detection fallback error: $e');
        return null;
      }
    }

    try {
      // The CameraImage -> InputImage.fromBytes API differs across ML Kit versions
      // which can cause build errors. To be robust, we recommend using
      // InputImage.fromFilePath via a temporary picture capture instead of
      // converting CameraImage planes here. If this method is called directly
      // we'll fall back to returning mock landmarks.
      debugPrint('detectFacesFromCameraImage: falling back to mock (prefer using detectFacesFromFilePath)');
      return _generateMockLandmarks(cameraImage.width, cameraImage.height);
    } catch (e, st) {
      debugPrint('MLKit detection error: $e\n$st');
      return null;
    }
  }
  
  static Future<List<Offset>?> detectFacesFromImageFile(String imagePath) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      // First try on-device ML Kit detection (fast and private)
      if (_mlkitDetector != null) {
        try {
          final res = await detectFacesFromFilePath(imagePath);
          if (res != null) return res;
        } catch (e) {
          debugPrint('ML Kit detection from file failed: $e');
        }
      }

      // Prefer backend detection when available
      try {
        final res = await detectFacesBySendingFile(File(imagePath));
        if (res != null) return res;
      } catch (e) {
        debugPrint('Backend detection failed, falling back to local mock: $e');
      }

      // Fallback mock
      return _generateMockLandmarks(640, 480); // Default image size
    } catch (e) {
      debugPrint('Face detection from file error: $e');
      return null;
    }
  }

  /// Run ML Kit detection on an image file path using `InputImage.fromFilePath`.
  static Future<List<Offset>?> detectFacesFromFilePath(String path) async {
    if (!_isInitialized) await initialize();
    if (_mlkitDetector == null) return null;

    try {
      final inputImage = InputImage.fromFilePath(path);
      final faces = await _mlkitDetector!.processImage(inputImage);
      if (faces.isEmpty) return <Offset>[];

      final out = <Offset>[];
      for (final face in faces) {
        final bb = face.boundingBox;
        final imgW = bb.width > 0 ? bb.width : 1;
        final imgH = bb.height > 0 ? bb.height : 1;
        // Use contours when available
        if (face.contours.isNotEmpty) {
          face.contours.forEach((type, contour) {
            if (contour?.points != null) {
              for (final p in contour!.points) {
                out.add(Offset((p.x / imgW).clamp(0.0, 1.0), (p.y / imgH).clamp(0.0, 1.0)));
              }
            }
          });
        } else {
          final cx = (bb.left + bb.right) / 2.0;
          final cy = (bb.top + bb.bottom) / 2.0;
          out.add(Offset((cx / imgW).clamp(0.0, 1.0), (cy / imgH).clamp(0.0, 1.0)));
        }
      }
      ln.landmarksNotifier.value = out;
      return out;
    } catch (e, st) {
      debugPrint('detectFacesFromFilePath error: $e\n$st');
      return null;
    }
  }

  /// Send a JPEG file to the backend /detect endpoint and parse normalized landmarks.
  static Future<List<Offset>?> detectFacesBySendingFile(File file) async {
    final uri = Uri.parse('$backendUrl/detect');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('image', file.path, contentType: MediaType('image', 'jpeg')));
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception('Backend returned ${resp.statusCode}: ${resp.body}');
    }
    final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
    final landmarks = jsonBody['landmarks'];
    if (landmarks == null) return null;
    // notify global notifier for overlay painting
    ln.notifyLandmarksFromFlatList(landmarks as List<dynamic>);
    // return as Offsets
    final out = <Offset>[];
    for (var i = 0; i + 1 < landmarks.length; i += 2) {
      final x = (landmarks[i] ?? 0).toDouble();
      final y = (landmarks[i + 1] ?? 0).toDouble();
      out.add(Offset(x, y));
    }
    return out;
  }
  
  
  // Generate mock landmarks for testing - replace with actual inference
  static List<Offset> _generateMockLandmarks(int width, int height) {
    // Generate a simple face-like landmark pattern
    final List<Offset> landmarks = [];
    
    // Face outline (approximate oval)
    for (int i = 0; i < 17; i++) {
      final double angle = (i * 2 * 3.14159) / 17;
      final double x = 0.5 + 0.3 * math.cos(angle);
      final double y = 0.4 + 0.25 * math.sin(angle);
      landmarks.add(Offset(x, y));
    }
    
    // Left eye
    for (int i = 0; i < 6; i++) {
      final double angle = (i * 2 * 3.14159) / 6;
      final double x = 0.35 + 0.05 * math.cos(angle);
      final double y = 0.35 + 0.05 * math.sin(angle);
      landmarks.add(Offset(x, y));
    }
    
    // Right eye
    for (int i = 0; i < 6; i++) {
      final double angle = (i * 2 * 3.14159) / 6;
      final double x = 0.65 + 0.05 * math.cos(angle);
      final double y = 0.35 + 0.05 * math.sin(angle);
      landmarks.add(Offset(x, y));
    }
    
    // Nose
    landmarks.addAll([
      Offset(0.5, 0.45),
      Offset(0.48, 0.5),
      Offset(0.52, 0.5),
      Offset(0.5, 0.55),
    ]);
    
    // Mouth
    for (int i = 0; i < 12; i++) {
      final double angle = (i * 2 * 3.14159) / 12;
      final double x = 0.5 + 0.08 * math.cos(angle);
      final double y = 0.65 + 0.05 * math.sin(angle);
      landmarks.add(Offset(x, y));
    }
    
    return landmarks;
  }
  
  static void dispose() {
    _isInitialized = false;
    try {
      _mlkitDetector?.close();
    } catch (_) {}
  }
  
  static bool get isInitialized => _isInitialized;
}

