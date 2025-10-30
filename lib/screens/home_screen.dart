import 'dart:async';

import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/session_manager.dart';
import '../services/api_service.dart';
import 'report_page.dart';

// Conditional imports for web
import '../utils/js_util_stub.dart' if (dart.library.html) '../utils/js_util_web.dart' as js_util;

import '../widgets/eyetracking_overlay.dart';
import '../utils/js_bridge.dart' as js_bridge;
import '../utils/landmark_notifier.dart' as ln;
import 'image_detection_page.dart';
import '../services/face_detection_service.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _streaming = false;
  bool _isRecording = false;
  final SessionManager _sessionManager = SessionManager();
  String _status = 'Idle';
  bool _processing = false;
  int _frameSkip = 3; // process every 3rd frame
  int _frameCount = 0;
  int _captureEveryFrames = 24; // capture once every N frames
  bool _permissionRequested = false;
  // key for measuring the web placeholder's position so we can position the DOM overlay
  final GlobalKey _webPlaceholderKey = GlobalKey();
  Timer? _overlayTimer;
  Timer? _serverTimer;
  bool _useBackend = true; // when true, APK will upload periodic JPEGs to backend
  String? _lastEndedSessionId;
  bool _showGenerateReport = false;
  // Metric state removed (metrics UI is hidden). Detection/overlay still active.

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
    // ML Kit face-level metrics listener removed (metrics UI hidden).
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
    if (!_isRecording) {
      // Start a new recording session
      try {
        await _startRecordingSession();
        setState(() => _isRecording = true);
      } catch (e) {
        setState(() => _status = 'Failed to start recording: $e');
        return;
      }
    } else {
      // Stop the current recording session
      try {
        await _stopRecordingSession();
        setState(() => _isRecording = false);
      } catch (e) {
        setState(() => _status = 'Failed to stop recording: $e');
        return;
      }
    }
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

  // Timer and detection state
  Timer? _detectionTimer;
  Stopwatch _recordingStopwatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;
  List<Map<String, dynamic>> _detectionResults = [];
  
  Future<void> _startRecordingSession() async {
    try {
      setState(() {
        _status = 'Starting session...';
        _isRecording = true;
        _recordingStopwatch.start();
        _recordingDuration = Duration.zero;
        _detectionResults.clear();
      });

      // Initialize session manager with your API key
      _sessionManager.initialize(apiKey: 'your-api-key-here'); // TODO: Get from secure storage
      
      // Start a new session
      await _sessionManager.startSession(
        userId: 'current-user-id', // TODO: Get from auth service
        deviceId: 'device-id',     // TODO: Get device ID
        metadata: {
          'app_version': '1.0.0',
          'platform': Platform.operatingSystem,
          'device_info': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        },
      );

      // Start the camera stream if not already started
      if (!_streaming) {
        await _toggleStream();
      }

      // Start periodic detection
      _startPeriodicDetection();
      
      // Start timer to update UI
      _detectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration = _recordingStopwatch.elapsed;
          });
        }
      });
      
      setState(() => _status = 'Recording...');
    } catch (e) {
      setState(() => _status = 'Error starting session: $e');
      rethrow;
    }
  }
  
  void _startPeriodicDetection() {
    // Process frames every 500ms (adjust as needed)
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_controller != null && _controller!.value.isInitialized && !_processing) {
        try {
          setState(() => _processing = true);
          
          // Capture frame
          final image = await _controller!.takePicture();
          final imageFile = File(image.path);
          
          // Detect faces
          final faces = await FaceDetectionService.detectFacesFromImageFile(imageFile.path);
          
          if (faces != null && faces.isNotEmpty) {
            // Process and send to backend
            final detectionData = {
              'timestamp': DateTime.now().toIso8601String(),
              'duration': _recordingStopwatch.elapsed.inMilliseconds,
              'face_count': faces.length,
              'metrics': faces.map((face) => {'x': face.dx, 'y': face.dy}).toList(),
            };
            
            _detectionResults.add(detectionData);
            
            // Send to backend
            if (_useBackend) {
              await _sendDetectionData(detectionData);
            }
            
            // Notify overlay about latest landmarks so the overlay painter updates.
            final List<Map<String, double>> landmarkMaps = faces.map((face) => {
              'x': face.dx,
              'y': face.dy,
            }).toList();
            ln.notifyLandmarksFromMaps(landmarkMaps);
          }
        } catch (e) {
          debugPrint('Error in periodic detection: $e');
        } finally {
          if (mounted) {
            setState(() => _processing = false);
          }
        }
      }
    });
  }
  
  Future<void> _sendDetectionData(Map<String, dynamic> data) async {
    try {
      // TODO: Implement your API call to send detection data
      // Example:
      // await ApiService.sendDetectionData(data);
      debugPrint('Sending detection data: $data');
    } catch (e) {
      debugPrint('Error sending detection data: $e');
    }
  }
  
  Future<void> _stopRecordingSession() async {
    try {
      // Stop timers
      _detectionTimer?.cancel();
      _recordingStopwatch.stop();
      
      // Stop the camera stream if needed
      if (_streaming) {
        await _toggleStream();
      }
      
      // End the current session
        if (_sessionManager.isActive) {
        // Save all detection results before ending session
        await _saveDetectionResults();
        // capture the session id before ending so we can generate a report
        final sid = _sessionManager.currentSessionId;
        await _sessionManager.endSession();
        // Ensure UI updates by using setState when changing visible state
        if (mounted) {
          setState(() {
            _lastEndedSessionId = sid;
            _showGenerateReport = true;
          });
        } else {
          // Fallback assignment if widget already disposed
          _lastEndedSessionId = sid;
          _showGenerateReport = true;
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording session: $e');
      rethrow;
    }
  }

  // Metric chips removed — metrics UI is hidden.

  // Simplified UI: use a single primary record button (see bottom controls).
  // The previous compact icon button was removed to reduce redundancy.

  Future<void> _saveDetectionResults() async {
    if (_detectionResults.isEmpty) return;
    
    try {
      // Save to local storage or send to server
      debugPrint('Saving ${_detectionResults.length} detection results');
      // TODO: Implement saving logic (e.g., save to local database or send to server)
    } catch (e) {
      debugPrint('Error saving detection results: $e');
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _recordingStopwatch.stop();
    _sessionManager.dispose();
    if (kIsWeb) js_bridge.removeLandmarkListener();
    _controller?.dispose();
    FaceDetectionService.dispose();
    super.dispose();
  }

  void _onLandmarks(List<Map<String, double>> pts) {
    // Publish landmarks to the global notifier so the overlay painter and other
    // services can consume them. Metrics computation was removed to simplify UI.
    if (pts.isEmpty) {
      ln.notifyLandmarksFromMaps([]);
      return;
    }
    ln.notifyLandmarksFromMaps(pts);
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

  Future<void> _toggleStream() async {
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
          // Local on-device path: use the image stream to count frames and capture once every N frames.
          _serverTimer?.cancel();
          _frameCount = 0;

          // Define listener as a variable so we can restart it after stopping/starting
          late void Function(CameraImage) imageListener;
          imageListener = (CameraImage image) async {
            try {
              _frameCount++;
              // Only capture on the configured interval and when not already processing
              if (_frameCount % _captureEveryFrames != 0) return;
              if (_processing) return;
              _processing = true;

              // Stop the image stream to safely take a picture
              try {
                await _controller?.stopImageStream();
              } catch (_) {}

              // Take a high-quality picture for ML Kit
              final xfile = await _controller!.takePicture();
              final List<Offset>? landmarks = await FaceDetectionService.detectFacesFromImageFile(xfile.path);
              if (landmarks != null && landmarks.isNotEmpty) {
                final List<Map<String, double>> landmarkMaps = landmarks.map((offset) => {
                  'x': offset.dx,
                  'y': offset.dy,
                }).toList();
                _onLandmarks(landmarkMaps);
              } else {
                _onLandmarks([]);
              }

              // cleanup
              try {
                final f = File(xfile.path);
                if (await f.exists()) await f.delete();
              } catch (_) {}

              // Restart the image stream to continue counting frames
              try {
                await _controller?.startImageStream(imageListener);
              } catch (e) {
                debugPrint('Error restarting image stream: $e');
              }
            } catch (e) {
              debugPrint('Frame-based capture error: $e');
            } finally {
              _processing = false;
            }
          };

          // Start the image stream to begin counting frames
          try {
            await _controller?.startImageStream(imageListener);
          } catch (e) {
            debugPrint('Failed to start image stream for frame counting: $e');
            // Fallback to periodic picture if image stream isn't supported
            _serverTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
              if (_controller == null || !_controller!.value.isInitialized) return;
              if (_processing) return;
              _processing = true;
              try {
                final xfile = await _controller!.takePicture();
                final List<Offset>? landmarks = await FaceDetectionService.detectFacesFromImageFile(xfile.path);
                if (landmarks != null && landmarks.isNotEmpty) {
                  final List<Map<String, double>> landmarkMaps = landmarks.map((offset) => {
                    'x': offset.dx,
                    'y': offset.dy,
                  }).toList();
                  _onLandmarks(landmarkMaps);
                } else {
                  _onLandmarks([]);
                }
                try {
                  final f = File(xfile.path);
                  if (await f.exists()) await f.delete();
                } catch (_) {}
              } catch (e) {
                debugPrint('Periodic MLKit capture fallback error: $e');
              } finally {
                _processing = false;
              }
            });
          }
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
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F1724),
      body: Stack(
        children: [
          // Main content
          Column(
            children: [
              // Status bar with timer
              Container(
                height: statusBarHeight,
                color: const Color(0xFF0F1724),
                padding: EdgeInsets.only(top: statusBarHeight > 0 ? 0 : 24), // Fallback for web
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      _isRecording 
                          ? '${_recordingDuration.inMinutes.toString().padLeft(2, '0')}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}'
                          : '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              // Camera preview area
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    top: statusBarHeight > 0 ? 12.0 : 28.0, // Increased top margin
                    left: 16.0,  // Added left margin
                    right: 16.0, // Added right margin
                    bottom: 8.0,  // Added bottom margin for balance
                  ),
                  child: kIsWeb
                      ? Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: const Text('Web camera placeholder', style: TextStyle(color: Colors.white54)),
                        )
                      : (controller != null && controller.value.isInitialized
                          ? const CameraPreviewPlaceholder()
                          : Center(
                              child: ElevatedButton(
                                onPressed: _initCamera,
                                child: const Text('Request Camera Permission'),
                              ),
                            )),
                ),
              ),
            ],
          ),
        ],
      ),
      // Bottom controls (kept as-is; metrics removed per user request)
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: const BoxDecoration(
          color: Color(0xFF071226),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onRecordPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_isRecording ? 'STOP' : 'RECORD', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
            if (_showGenerateReport && _lastEndedSessionId != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  // fetch report and navigate
                  try {
                    final report = await ApiService.getSessionReport(_lastEndedSessionId!);
                    if (mounted) {
                      // navigate to report page
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportPage(report: report)));
                      setState(() { _showGenerateReport = false; });
                    }
                  } catch (e) {
                    setState(() { _status = 'Failed to generate report: $e'; });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Generate Session Report', style: TextStyle(fontSize: 16)),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            // bottom navigation mimic
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                const _BottomNavItem(icon: Icons.monitor_heart, label: 'Monitor', active: true),

                // Dashboard navigation
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardPage())),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dashboard, color: Colors.white54),
                        SizedBox(height: 6),
                        Text('Dashboard', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ),

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

                // Settings navigation (await settings changes)
                InkWell(
                  onTap: () async {
                    final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(useBackend: _useBackend, frameSkip: _frameSkip)));
                    if (result is Map<String, dynamic>) {
                      setState(() {
                        if (result.containsKey('useBackend')) _useBackend = result['useBackend'] as bool;
                        if (result.containsKey('frameSkip')) _frameSkip = result['frameSkip'] as int;
                      });
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.settings, color: Colors.white54),
                        SizedBox(height: 6),
                        Text('Settings', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
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

// Lightweight private widget that builds the actual CameraPreview + overlay.
// Kept separate so we can use a const placeholder above and still render the
// real preview with the runtime controller below using an InheritedBuilder.
class CameraPreviewPlaceholder extends StatelessWidget {
  const CameraPreviewPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Find the HomeScreen state via ancestor; this is acceptable for this simple app.
    final state = context.findAncestorStateOfType<_HomeScreenState>();
    final controller = state?._controller;
    if (controller != null && controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          const EyetrackingOverlay(),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
