import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:js_util' as js_util;
import 'package:http/http.dart' as http;
import 'dart:math' as math;

class ImageDetectionPage extends StatefulWidget {
  const ImageDetectionPage({Key? key}) : super(key: key);

  @override
  State<ImageDetectionPage> createState() => _ImageDetectionPageState();
}

class _ImageDetectionPageState extends State<ImageDetectionPage> {
  XFile? _imageFile;
  Uint8List? _imageBytes;
  String _status = 'Pick an image to analyze';
  int _landmarkCount = 0;
  List<Offset>? _landmarksNormalized;
  double? _attentionPercent;
  double? _drowsinessPercent;

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
      if (file == null) return;
      setState(() {
        _imageFile = file;
        _status = 'Loaded image';
        _landmarkCount = 0;
      });

      // read bytes for mobile preview
      try {
        _imageBytes = await file.readAsBytes();
      } catch (_) {
        _imageBytes = null;
      }

      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        final dataUrl = _bytesToDataUrl(bytes, file.mimeType ?? 'image/jpeg');
        setState(() => _status = 'Processing image (client-side) ...');
        bool handled = false;
        try {
          // try client-side JS pipeline first
          if (js_util.hasProperty(js_util.globalThis, 'processImageDataUrl')) {
            final promise = js_util.callMethod(js_util.globalThis, 'processImageDataUrl', [dataUrl]);
            final result = await js_util.promiseToFuture(promise);
            if (result is List && result.isNotEmpty) {
              final pts = _flattenResultToOffsets(result);
              final metrics = _computeMetricsFromNormalized(pts);
              setState(() {
                _landmarkCount = pts.length;
                _landmarksNormalized = pts;
                _attentionPercent = metrics['attention'];
                _drowsinessPercent = metrics['drowsiness'];
                _status = 'Found $_landmarkCount landmarks (client)';
              });
              handled = true;
            }
          }
        } catch (e) {
          // client pipeline failed; we'll try backend
          handled = false;
        }

        if (!handled) {
          setState(() => _status = 'Client detection failed — trying backend...');
          final backendOk = await _callBackendWithDataUrl(dataUrl);
          if (!backendOk) {
            setState(() => _status = 'No landmarks from client or backend');
          }
        }
      } else {
        // Mobile/desktop placeholder: we don't yet have on-device image model in this prototype.
        setState(() => _status = 'Image selected (mobile): processing is not implemented yet');
      }
    } catch (e) {
      setState(() => _status = 'Image pick error: $e');
    }
  }

  List<Offset> _flattenResultToOffsets(List result) {
    final flat = <double>[];
    for (var v in result) {
      if (v is num) flat.add(v.toDouble());
    }
    final pts = <Offset>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      pts.add(Offset(flat[i], flat[i + 1]));
    }
    return pts;
  }

  Future<bool> _callBackendWithDataUrl(String dataUrl) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:5000/detect');
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: '{"dataUrl": "${dataUrl.replaceAll('\n', '')}"}').timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = resp.body;
        // parse simple JSON without adding json package; use dart:convert
        final json = body.isNotEmpty ? Uri.decodeComponent(body) : null;
        // safer: use dart:convert
        final parsed = body.isNotEmpty ? jsonDecode(body) : null;
        if (parsed != null && parsed['landmarks'] != null) {
          final result = parsed['landmarks'] as List;
          final pts = _flattenResultToOffsets(result);
          final metrics = _computeMetricsFromNormalized(pts);
          setState(() {
            _landmarkCount = pts.length;
            _landmarksNormalized = pts;
            _attentionPercent = metrics['attention'];
            _drowsinessPercent = metrics['drowsiness'];
            _status = 'Found $_landmarkCount landmarks (backend)';
          });
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  String _bytesToDataUrl(Uint8List bytes, String mime) {
    final base64Data = base64Encode(bytes);
    return 'data:$mime;base64,$base64Data';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Detection')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image),
              label: const Text('Pick image'),
            ),
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            if (_imageFile != null)
              Expanded(
                child: Center(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final widget = kIsWeb
                        ? Image.network(_imageFile!.path, fit: BoxFit.contain)
                        : (_imageBytes != null
                            ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                            : FutureBuilder<Uint8List>(
                                future: awaitReadBytesSafe(_imageFile!),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                    return Image.memory(snapshot.data!, fit: BoxFit.contain);
                                  }
                                  return const Center(child: CircularProgressIndicator());
                                },
                              ));

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(child: widget),
                        if (_landmarksNormalized != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ImageLandmarkPainter(_landmarksNormalized!),
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Icon(Icons.photo, size: 80, color: Colors.white10),
                ),
              ),
            const SizedBox(height: 12),
            if (_landmarkCount > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Landmarks detected: $_landmarkCount', style: const TextStyle(color: Colors.white)),
                  if (_attentionPercent != null) Text('Attention: ${_attentionPercent}%', style: const TextStyle(color: Colors.white70)),
                  if (_drowsinessPercent != null) Text('Drowsiness: ${_drowsinessPercent}%', style: const TextStyle(color: Colors.white70)),
                ],
              ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFF071226),
    );
  }
}

// Helper that reads bytes but avoids holding state in build; used only for non-web case image display fallback.
Future<Uint8List> awaitReadBytesSafe(XFile file) async {
  try {
    return await file.readAsBytes();
  } catch (_) {
    return Uint8List(0);
  }
}

Map<String, double> _computeMetricsFromNormalized(List<Offset> pts) {
  if (pts.isEmpty) return {'attention': 0.0, 'drowsiness': 0.0};
  double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  final area = (maxX - minX) * (maxY - minY);
  final centroidX = (minX + maxX) / 2.0;
  final centeredFactor = (1.0 - (2 * (centroidX - 0.5).abs())).clamp(0.0, 1.0);
  final sizeFactor = area.clamp(0.0, 1.0);
  final attention = (centeredFactor * 0.6 + sizeFactor * 0.4) * 100.0;

  // EAR-like metric (best-effort using MediaPipe indices)
  double leftEAR = 0.0, rightEAR = 0.0;
  final left = [33, 160, 158, 133, 153, 144];
  final right = [362, 385, 387, 263, 373, 380];
  bool haveEyes = pts.length > 400;
  double distIdx(List<Offset> list, int i, int j) {
    final a = list[i];
    final b = list[j];
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
  if (haveEyes) {
    try {
      leftEAR = (distIdx(pts, left[1], left[5]) + distIdx(pts, left[2], left[4])) / (2.0 * distIdx(pts, left[0], left[3]));
      rightEAR = (distIdx(pts, right[1], right[5]) + distIdx(pts, right[2], right[4])) / (2.0 * distIdx(pts, right[0], right[3]));
    } catch (_) {
      leftEAR = 0.0;
      rightEAR = 0.0;
    }
  }
  final avgEar = ((leftEAR + rightEAR) / 2.0).clamp(0.0, 1.0);
  final normalized = ((0.28 - avgEar) / 0.13).clamp(0.0, 1.0);
  final drowsiness = normalized * 100.0;
  return {'attention': double.parse(attention.toStringAsFixed(1)), 'drowsiness': double.parse(drowsiness.toStringAsFixed(1))};
}

class _ImageLandmarkPainter extends CustomPainter {
  final List<Offset> normalized;
  _ImageLandmarkPainter(this.normalized);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color.fromARGB(230, 0, 255, 140)..style = PaintingStyle.fill;
    final stroke = Paint()..color = const Color.fromARGB(200, 0, 200, 150)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    for (final p in normalized) {
      final dx = p.dx * size.width;
      final dy = p.dy * size.height;
      canvas.drawCircle(Offset(dx, dy), 3.0, paint);
    }
    if (normalized.length > 1) {
      final path = Path();
      path.moveTo(normalized[0].dx * size.width, normalized[0].dy * size.height);
      for (var i = 1; i < normalized.length; i++) {
        path.lineTo(normalized[i].dx * size.width, normalized[i].dy * size.height);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ImageLandmarkPainter oldDelegate) => oldDelegate.normalized != normalized;
}
