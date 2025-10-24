import 'dart:async';

import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// Conditional imports for web
import '../utils/js_util_stub.dart' if (dart.library.html) '../utils/js_util_web.dart' as js_util;

import '../widgets/eyetracking_overlay.dart';
import '../utils/js_bridge.dart' as js_bridge;
import 'image_detection_page.dart';
import '../services/face_detection_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _streaming = false;
  String _status = 'Idle';
  bool _processing = false;
  int _frameSkip = 3; // process every 3rd frame
  int _frameCount = 0;
  bool _permissionRequested = false;
  // key for measuring the web placeholder's position so we can position the DOM overlay
  final GlobalKey _webPlaceholderKey = GlobalKey();
  Timer? _overlayTimer;
  Timer? _serverTimer;
  bool _useBackend = true; // when true, APK will upload periodic JPEGs to backend
  // realtime metrics from web landmarks
  int _landmarkCount = 0;
  double _faceAreaPercent = 0; // 0..100
  double _attentionPercent = 0;
  double _drowsinessPercent = 0;
  int _blinkCount = 0;
  bool _blinkInProgress = false;
  final List<double> _earHistory = [];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initCamera();
      _initializeFaceDetection();
    } else {
      setState(() => _status = 'Web platform — use Web Camera Test');
      // listen for JS landmark events
      js_bridge.addLandmarkListener(_onLandmarks);
    }
  }
  
  Future<void> _initializeFaceDetection() async {
    try {
      final bool initialized = await FaceDetectionService.initialize();
      if (initialized) {
        setState(() => _status = 'Face detection ready');
      } else {
        setState(() => _status = 'Face detection failed to initialize');
      }
    } catch (e) {
      setState(() => _status = 'Face detection error: $e');
    }
  }

  // Unified handler for the Record button. Provides immediate UI feedback and
  // calls the appropriate start/stop functions for web vs native.
  Future<void> _onRecordPressed() async {
    if (kIsWeb) {
      if (_streaming) {
        setState(() => _status = 'Stopping web camera...');
        await _stopWebCamera();
      } else {
        setState(() => _status = 'Starting web camera...');
        try {
          await _startWebCamera();
        } catch (e) {
          setState(() => _status = 'Web camera error: $e');
        }
      }
    } else {
      // native path toggles image stream
      setState(() => _status = _streaming ? 'Stopping...' : 'Starting...');
      _toggleStream();
    }
  }

  @override
  void dispose() {
    if (kIsWeb) js_bridge.removeLandmarkListener();
    _controller?.dispose();
    FaceDetectionService.dispose();
    super.dispose();
  }

  void _onLandmarks(List<Map<String, double>> pts) {
    if (pts.isEmpty) {
      setState(() {
        _landmarkCount = 0;
        _faceAreaPercent = 0;
        _attentionPercent = 0;
        _drowsinessPercent = 0;
      });
      return;
    }

    // compute bounding box in normalized coords
    double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      final x = p['x'] ?? 0.0;
      final y = p['y'] ?? 0.0;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    final area = (maxX - minX) * (maxY - minY); // normalized
    final percent = (area * 100).clamp(0.0, 100.0);

    // compute attention: centeredness and size
    final centroidX = (minX + maxX) / 2.0;
    final centeredFactor = (1.0 - (2 * (centroidX - 0.5).abs())).clamp(0.0, 1.0);
    final sizeFactor = area.clamp(0.0, 1.0);
    final attention = (centeredFactor * 0.6 + sizeFactor * 0.4) * 100.0;

    // compute EAR for eyes if enough landmarks
    double leftEAR = 0.0, rightEAR = 0.0;
    final left = [33, 160, 158, 133, 153, 144];
    final right = [362, 385, 387, 263, 373, 380];
    bool haveEyes = pts.length > 400; // simple check
    double dist(int i, int j) {
      final a = pts[i];
      final b = pts[j];
      final dx = (a['x'] ?? 0) - (b['x'] ?? 0);
      final dy = (a['y'] ?? 0) - (b['y'] ?? 0);
      return math.sqrt(dx * dx + dy * dy);
    }
    if (haveEyes) {
      try {
        leftEAR = (dist(left[1], left[5]) + dist(left[2], left[4])) / (2.0 * dist(left[0], left[3]));
        rightEAR = (dist(right[1], right[5]) + dist(right[2], right[4])) / (2.0 * dist(right[0], right[3]));
      } catch (_) {
        leftEAR = 0.0; rightEAR = 0.0;
      }
    }

    final currentEar = ((leftEAR + rightEAR) / 2.0);
    _earHistory.add(currentEar);
    if (_earHistory.length > 30) _earHistory.removeAt(0);
    final avgEar = _earHistory.isEmpty ? 0.0 : _earHistory.reduce((a, b) => a + b) / _earHistory.length;

    // drowsiness mapping (lower EAR => more drowsy). map EAR approx [0.15..0.35]
    final normalized = ((0.28 - avgEar) / 0.13).clamp(0.0, 1.0);
    final drowsiness = normalized * 100.0;

    // blink detection
    final blinkThresh = 0.20;
    if (!_blinkInProgress && avgEar > 0 && avgEar < blinkThresh) {
      _blinkInProgress = true;
    }
    if (_blinkInProgress && avgEar >= blinkThresh) {
      _blinkInProgress = false;
      _blinkCount += 1;
    }

    setState(() {
      _landmarkCount = pts.length;
      _faceAreaPercent = double.parse(percent.toStringAsFixed(1));
      _attentionPercent = double.parse(attention.clamp(0.0, 100.0).toStringAsFixed(1));
      _drowsinessPercent = double.parse(drowsiness.toStringAsFixed(1));
    });
  }

  // (Duplicate short handler removed.) The comprehensive `_onLandmarks` above
  // computes attention, drowsiness, blink count and updates all related state.

  Future<void> _initCamera() async {
    _permissionRequested = true;
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _status = 'Camera permission required');
      return;
    }

    try {
      _cameras = await availableCameras();
      final front = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first);

      _controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      setState(() {});
    } catch (e) {
      setState(() => _status = 'Camera init error: $e');
    }
  }

  void _toggleStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (!_streaming) {
      setState(() {
        _status = 'Streaming';
        _streaming = true;
      });

      if (_useBackend) {
        // Start periodic JPEG captures and send to backend
        _serverTimer?.cancel();
        _serverTimer = Timer.periodic(const Duration(milliseconds: 700), (t) async {
          try {
            if (_controller == null || !_controller!.value.isInitialized) return;
            final xfile = await _controller!.takePicture();
            // Let the FaceDetectionService handle sending and notifying landmarks
            await FaceDetectionService.detectFacesBySendingFile(File(xfile.path));
            // cleanup file
            try {
              final f = File(xfile.path);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          } catch (e) {
            debugPrint('Periodic backend upload error: $e');
          }
        });
      } else {
        // Local image stream path (existing placeholder pipeline)
        await _controller!.startImageStream((image) async {
          // Lightweight frame sampling + concurrency guard
          _frameCount = (_frameCount + 1) % _frameSkip;
          if (_frameCount != 0) return; // skip frames

          if (_processing) return; // already processing
          _processing = true;

          try {
            // Real face detection using our service
            final List<Offset>? landmarks = await FaceDetectionService.detectFacesFromCameraImage(image);
            if (landmarks != null && landmarks.isNotEmpty) {
              final List<Map<String, double>> landmarkMaps = landmarks.map((offset) => {
                'x': offset.dx,
                'y': offset.dy,
              }).toList();
              _onLandmarks(landmarkMaps);
            } else {
              _onLandmarks([]);
            }
          } catch (e) {
            debugPrint('Face detection error: $e');
            _onLandmarks([]);
          } finally {
            _processing = false;
          }
        });
      }
    } else {
      // stopping
      if (_useBackend) {
        _serverTimer?.cancel();
        _serverTimer = null;
      } else {
        try {
          await _controller!.stopImageStream();
        } catch (_) {}
      }
      setState(() {
        _streaming = false;
        _status = 'Idle';
      });
    }
  }

  // Web-specific start/stop using JS interop (calls functions defined in web/index.html)
  Future<void> _startWebCamera() async {
    try {
      // ensure the overlay is positioned first (may be a no-op if widget not laid out yet)
      WidgetsBinding.instance.addPostFrameCallback((_) => _positionWebOverlay());

      // keep positioning periodically while streaming to handle layout changes
      _overlayTimer?.cancel();
      _overlayTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _positionWebOverlay());

      await js_util.promiseToFuture(js_util.callMethod(js_util.globalThis, 'startFaceDetection', []));
      // Make sure overlay is on top of Flutter canvas
      try {
        js_util.callMethod(js_util.globalThis, 'bringOverlayToFront', []);
      } catch (_) {}
      setState(() {
        _streaming = true;
        _status = 'Web streaming';
      });
    } catch (e) {
      setState(() => _status = 'Web camera error: $e');
    }
  }

  Future<void> _stopWebCamera() async {
    try {
      js_util.callMethod(js_util.globalThis, 'stopFaceDetection', []);
      // hide overlay and stop periodic repositioning
      try {
        js_util.callMethod(js_util.globalThis, 'hideOverlay', []);
      } catch (_) {}
      _overlayTimer?.cancel();
      _overlayTimer = null;
      setState(() {
        _streaming = false;
        _status = 'Idle';
      });
    } catch (e) {
      setState(() => _status = 'Web stop error: $e');
    }
  }

  // Measure the Flutter placeholder and inform the JS overlay where to position itself.
  Future<void> _positionWebOverlay() async {
    if (!kIsWeb) return;
    try {
      final ctx = _webPlaceholderKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final offset = box.localToGlobal(Offset.zero);
      final size = box.size;
      js_util.callMethod(js_util.globalThis, 'positionOverlay', [offset.dx, offset.dy, size.width, size.height]);
      // keep overlay visually on top
      try {
        js_util.callMethod(js_util.globalThis, 'bringOverlayToFront', []);
      } catch (_) {}
    } catch (e) {
      // ignore positioning errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1724),
      appBar: AppBar(
        title: const Text('NeuroVision Tracker'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // Top half: camera area (mobile camera preview or web placeholder)
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20)),
                child: SizedBox.expand(
                  child: kIsWeb
                      ? Container(
                          margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1220),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    // NOTE: Web video is inserted into the DOM by the JS in `web/index.html`.
                                    // We show a visual placeholder here — the actual <video> element will be
                                    // displayed on top of the app when you grant camera permission.
                                    Positioned.fill(
                                      child: Padding(
                                        key: _webPlaceholderKey,
                                        padding: const EdgeInsets.all(6),
                                        child: Center(
                                          child: Text(
                                            'Web camera will appear here after permission',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white54),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Row(
                                        children: [
                                          _Badge(text: 'RECORDING', color: Colors.redAccent),
                                          const SizedBox(width: 8),
                                          _Badge(text: 'SYNC', color: Colors.indigoAccent),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 12,
                                      right: 12,
                                      child: _Badge(text: 'CV: 21 FPS', color: Colors.purpleAccent),
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : (controller != null && controller.value.isInitialized
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B1220),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CameraPreview(controller),
                                        const EyetrackingOverlay(),
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: Row(
                                            children: [
                                              _Badge(text: 'RECORDING', color: Colors.redAccent),
                                              const SizedBox(width: 8),
                                              _Badge(text: 'SYNC', color: Colors.indigoAccent),
                                            ],
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 12,
                                          right: 12,
                                          child: _Badge(text: 'CV: 21 FPS', color: Colors.purpleAccent),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: _permissionRequested
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.camera_alt, color: Colors.white54, size: 48),
                                        const SizedBox(height: 8),
                                        Text(_status, style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 10),
                                        ElevatedButton(onPressed: _initCamera, child: const Text('Retry Permission'))
                                      ],
                                    )
                                  : ElevatedButton(onPressed: _initCamera, child: const Text('Request Camera Permission')),
                            )),
                ),
              ),
            ),
          ),

          // Bottom half: metrics and controls (colorful)
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFF071226),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Live Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white), overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _streaming ? 'L: $_landmarkCount  00:12' : '00:00',
                          style: const TextStyle(color: Colors.white54),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SizedBox(width: 8),
                          _AnalyticsCard(title: 'Attention', percent: _attentionPercent.toInt(), color: Colors.deepOrange),
                        SizedBox(width: 12),
                        _AnalyticsCard(title: 'Drowsiness', percent: _drowsinessPercent.toInt(), color: Colors.amber),
                        SizedBox(width: 12),
                        _AnalyticsCard(title: 'Facial', percent: _faceAreaPercent.toInt(), color: Colors.cyan),
                        SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FloatingActionButton(
                        backgroundColor: Colors.deepPurpleAccent,
                        mini: true,
                        onPressed: () {
                          // sample play action
                        },
                        child: const Icon(Icons.play_arrow),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _onRecordPressed,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: Text(_streaming ? 'Stop Recording' : 'Record', style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  // bottom navigation mimic
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      const _BottomNavItem(icon: Icons.monitor_heart, label: 'Monitor', active: true),
                      const _BottomNavItem(icon: Icons.dashboard, label: 'Dashboard'),
                      InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImageDetectionPage())),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image, color: Colors.white54),
                              SizedBox(height: 6),
                              Text('Image', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const _BottomNavItem(icon: Icons.settings, label: 'Settings'),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({Key? key, required this.text, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6)],
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final int percent;
  final Color color;
  const _AnalyticsCard({Key? key, required this.title, required this.percent, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2130),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70)),
              Text('$percent%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Icon(Icons.insights, size: 36, color: color.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _BottomNavItem({Key? key, required this.icon, required this.label, this.active = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: active ? Colors.deepPurpleAccent : Colors.white54),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 12)),
      ],
    );
  }
}
