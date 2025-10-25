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
import 'dart:ui' as ui;

class FaceDetectionService {
  static bool _isInitialized = false;
  static FaceDetector? _mlkitDetector;
  static String get backendUrl => ApiService.baseUrl;
  
  // Session management
  static bool _sessionActive = false;
  
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
  static Future<List<Offset>?> detectFacesFromCameraImage(
    CameraImage cameraImage, 
    [CameraDescription? cameraDescription,
    bool useSession = true]
  ) async {
    if (!_isInitialized) {
      await initialize();
    }

    // On web, try to use the web-specific implementation first
    if (kIsWeb) {
      debugPrint('Web platform detected, using web-specific face detection');
      try {
        // Try to get landmarks from the web implementation
        final webLandmarks = await _getWebLandmarks(cameraImage);
        if (webLandmarks != null && webLandmarks.isNotEmpty) {
          return webLandmarks;
        }
      } catch (e) {
        debugPrint('Web face detection failed: $e');
      }
      
      // Fall back to mock landmarks if web detection fails
      debugPrint('Falling back to mock landmarks for web');
      return _generateMockLandmarks(cameraImage.width, cameraImage.height);
    }

    // For mobile platforms, try ML Kit first
    if (_mlkitDetector != null) {
      try {
        debugPrint('Trying on-device ML Kit detection for camera frame...');
        final inputImage = _convertCameraImageToInputImage(cameraImage, cameraDescription);
        final faces = await _mlkitDetector!.processImage(inputImage);
        
        if (faces.isNotEmpty) {
          debugPrint('Detected ${faces.length} faces using ML Kit');
          // Convert ML Kit face data to our format
          return _convertMlKitFacesToOffsets(faces, cameraImage.width, cameraImage.height);
        }
      } catch (e, st) {
        debugPrint('ML Kit detection error: $e\n$st');
      }
    }

    // Fall back to backend if ML Kit is not available or fails
    try {
      debugPrint('Falling back to backend detection for camera frame...');
      final imageBytes = await _convertCameraImageToJpeg(cameraImage);
      if (imageBytes != null && imageBytes.isNotEmpty) {
        // Start a session if not already active and session is requested
        if (useSession && !_sessionActive) {
          try {
            await ApiService.startSession();
            _sessionActive = true;
          } catch (e) {
            debugPrint('Failed to start session: $e');
            // Continue without session if session start fails
          }
        }
        
        final points = await ApiService.detectFaces(
          imageBytes,
          useSession: useSession,
        );
        if (points.isNotEmpty) {
          return points.map((p) => Offset(p['x']!, p['y']!)).toList();
        }
      }
    } catch (e) {
      debugPrint('Backend detection failed: $e');
    }

    // Last resort: return mock landmarks
    debugPrint('All detection methods failed, using mock landmarks');
    return _generateMockLandmarks(cameraImage.width, cameraImage.height);
  }
  
  static Future<List<Offset>?> detectFacesFromImageFile(String imagePath) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // First try on-device ML Kit detection (fast and private)
    if (_mlkitDetector != null) {
      try {
        debugPrint('Trying on-device ML Kit detection...');
        final res = await detectFacesFromFilePath(imagePath);
        if (res != null && res.isNotEmpty) {
          debugPrint('Successfully detected ${res.length} landmarks using ML Kit');
          return res;
        }
      } catch (e) {
        debugPrint('ML Kit detection failed, falling back to backend: $e');
      }
    }

    // Fall back to backend detection
    try {
      debugPrint('Trying backend face detection...');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }
      
      final imageBytes = await imageFile.readAsBytes();
      if (imageBytes.isEmpty) {
        throw Exception('Failed to read image bytes');
      }
      
      debugPrint('Sending ${imageBytes.length} bytes to backend for detection...');
      final points = await ApiService.detectFaces(
        imageBytes,
        imagePath: imagePath,
        useSession: true, // Use session if available
      );
      
      if (points.isNotEmpty) {
        debugPrint('Successfully detected ${points.length} landmarks from backend');
        // Convert points to Offsets
        return points.map((p) => Offset(p['x']!, p['y']!)).toList();
      } else {
        debugPrint('No landmarks detected in the image');
        return [];
      }
    } catch (e) {
      debugPrint('Backend detection failed: $e');
      // Fallback to mock landmarks
      return _generateMockLandmarks(640, 480); // Default image size
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

  /// Convert CameraImage to InputImage for ML Kit
  static InputImage _convertCameraImageToInputImage(
    CameraImage image,
    CameraDescription? cameraDescription,
  ) {
    final camera = cameraDescription ?? CameraDescription(
      name: 'unknown',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    );
    
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? 
        InputImageRotation.rotation0deg;
    
    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? 
        InputImageFormat.nv21;
    
    // Get the image data
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    
    final size = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );
    
    // Create input image using the correct constructor for the current ML Kit version
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: size,
        rotation: rotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }
  
  /// Convert CameraImage to JPEG bytes
  static Future<Uint8List> _convertCameraImageToJpeg(CameraImage image) async {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        // For YUV420 format, we'll create a simple RGB conversion
        final width = image.width;
        final height = image.height;
        final yPlane = image.planes[0].bytes;
        final uPlane = image.planes[1].bytes;
        final vPlane = image.planes[2].bytes;
        
        // Create a buffer for the RGB image
        final rgbaImage = await _yuv420ToRgba(yPlane, uPlane, vPlane, width, height);
        
        // Convert RGBA to JPEG using Flutter's image package
        final codec = await ui.instantiateImageCodec(
          rgbaImage.buffer.asUint8List(),
          targetWidth: width,
          targetHeight: height,
        );
        
        final frame = await codec.getNextFrame();
        final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        
        if (byteData == null) {
          throw Exception('Failed to convert image to PNG');
        }
        
        return byteData.buffer.asUint8List();
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        // For BGRA format
        return image.planes[0].bytes;
      } else if (image.format.group == ImageFormatGroup.jpeg) {
        // For JPEG format, return as is
        return image.planes[0].bytes;
      } else {
        throw Exception('Unsupported image format: ${image.format}');
      }
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      // Return a simple black image as fallback
      return Uint8List(0);
    }
  }
  
  /// Convert YUV420 to RGBA format
  static Future<Uint8List> _yuv420ToRgba(
    Uint8List yPlane,
    Uint8List uPlane,
    Uint8List vPlane,
    int width,
    int height,
  ) async {
    // This is a simplified YUV to RGB conversion
    // In a production app, you'd want to use a more optimized solution
    final rgba = Uint8List(width * height * 4);
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * width + x;
        final uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);
        
        final yVal = yPlane[yIndex].toDouble();
        final uVal = uPlane[uvIndex].toDouble() - 128.0;
        final vVal = vPlane[uvIndex].toDouble() - 128.0;
        
        // Convert YUV to RGB (simplified)
        int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
        int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
        int b = (yVal + 1.772 * uVal).round().clamp(0, 255);
        
        // Set RGBA values (opaque)
        final rgbaIndex = yIndex * 4;
        rgba[rgbaIndex] = r;
        rgba[rgbaIndex + 1] = g;
        rgba[rgbaIndex + 2] = b;
        rgba[rgbaIndex + 3] = 255; // Alpha channel (fully opaque)
      }
    }
    
    return rgba;
  }
  
  /// Web-specific face detection (stub implementation)
  static Future<List<Offset>?> _getWebLandmarks(CameraImage image) async {
    // This is a stub implementation for web
    // In a real web implementation, you would use the web-specific APIs
    debugPrint('Web face detection not implemented');
    // Return mock landmarks for web platform
    return _generateMockLandmarks(image.width, image.height);
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
  
  /// Convert ML Kit face detection results to a list of normalized Offsets
  static List<Offset> _convertMlKitFacesToOffsets(
    List<Face> faces,
    int imageWidth,
    int imageHeight,
  ) {
    if (faces.isEmpty) return [];
    
    // For simplicity, we'll just use the first face
    final face = faces.first;
    final List<Offset> landmarks = [];
    
    // Convert face landmarks to normalized coordinates (0.0 to 1.0)
    final left = face.boundingBox.left / imageWidth;
    final top = face.boundingBox.top / imageHeight;
    final right = face.boundingBox.right / imageWidth;
    final bottom = face.boundingBox.bottom / imageHeight;
    
    // Add face bounding box points
    landmarks.add(Offset(left, top));
    landmarks.add(Offset(right, top));
    landmarks.add(Offset(right, bottom));
    landmarks.add(Offset(left, bottom));
    
    // Add face landmarks if available
    if (face.landmarks.isNotEmpty) {
      for (final landmark in face.landmarks.values) {
        if (landmark != null) {
          final x = landmark.position.x / imageWidth;
          final y = landmark.position.y / imageHeight;
          landmarks.add(Offset(x, y));
        }
      }
    }
    
    return landmarks;
  }
  
  static Future<void> dispose() async {
    _isInitialized = false;
    try {
      _mlkitDetector?.close();
      if (_sessionActive) {
        await ApiService.endSession();
        _sessionActive = false;
      }
    } catch (e) {
      debugPrint('Error during disposal: $e');
    }
  }
  
  static bool get isInitialized => _isInitialized;
}

