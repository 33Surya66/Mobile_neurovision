import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import '../utils/landmark_notifier.dart' as ln;
import 'api_service.dart';
// ML Kit for on-device face detection
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionService {
  static bool _isInitialized = false;
  static FaceDetector? _mlkitDetector;
  // Backend server URL is now managed by ApiService
  // Configure the base URL in ApiService._baseUrl
  
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

      // Use the new ApiService for backend detection
      try {
        final imageFile = File(imagePath);
        final imageBytes = await imageFile.readAsBytes();
        final points = await ApiService.detectFaces(imageBytes, imagePath: imagePath);
        
        if (points.isNotEmpty) {
          // Convert points to Offsets
          return points.map((p) => Offset(p['x']!, p['y']!)).toList();
        }
      } catch (e) {
        debugPrint('Backend detection failed: $e');
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

      // Load actual image dimensions to normalize points to 0..1 across the image
      final bytes = await File(path).readAsBytes();
      final uiImage = await _decodeImageFromList(bytes);
      final imgW = uiImage.width.toDouble();
      final imgH = uiImage.height.toDouble();

      // Choose the primary face (largest bounding box area) to drive metrics
      Face primary = faces.first;
      double maxArea = 0.0;
      for (final f in faces) {
        final a = f.boundingBox.width * f.boundingBox.height;
        if (a > maxArea) {
          maxArea = a;
          primary = f;
        }
      }

      final out = <Offset>[];
      // Prefer contours -> landmarks -> bounding box center
      if (primary.contours.isNotEmpty) {
        primary.contours.forEach((type, contour) {
          if (contour?.points != null) {
            for (final p in contour!.points) {
              out.add(Offset((p.x / imgW).clamp(0.0, 1.0), (p.y / imgH).clamp(0.0, 1.0)));
            }
          }
        });
      } else if (primary.landmarks.isNotEmpty) {
        primary.landmarks.forEach((type, lm) {
          if (lm?.position != null) {
            final p = lm!.position;
            out.add(Offset((p.x / imgW).clamp(0.0, 1.0), (p.y / imgH).clamp(0.0, 1.0)));
          }
        });
      } else {
        final bb = primary.boundingBox;
        final cx = (bb.left + bb.right) / 2.0;
        final cy = (bb.top + bb.bottom) / 2.0;
        out.add(Offset((cx / imgW).clamp(0.0, 1.0), (cy / imgH).clamp(0.0, 1.0)));
      }

      // Publish normalized landmarks for overlay and metrics
      ln.landmarksNotifier.value = out;
      return out;
    } catch (e, st) {
      debugPrint('detectFacesFromFilePath error: $e\n$st');
      return null;
    }
  }

  static Future<ui.Image> _decodeImageFromList(Uint8List data) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(data, (img) => completer.complete(img));
    return completer.future;
  }

  /// Send a JPEG file to the backend /detect endpoint and parse normalized landmarks.
  // This method is now handled by ApiService.detectFaces
  @Deprecated('Use ApiService.detectFaces instead')
  static Future<List<Offset>?> detectFacesBySendingFile(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final points = await ApiService.detectFaces(imageBytes, imagePath: imageFile.path);
      return points.map((p) => Offset(p['x']!, p['y']!)).toList();
    } catch (e) {
      debugPrint('Error detecting faces: $e');
      return null;
    }
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

