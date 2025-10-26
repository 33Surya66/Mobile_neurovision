import 'package:flutter/material.dart';
import 'face_painter.dart';
import '../services/metrics_service.dart';
import '../utils/landmark_notifier.dart' as ln;

class EyetrackingOverlay extends StatelessWidget {
  const EyetrackingOverlay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<List<Offset>>(
        valueListenable: ln.landmarksNotifier,
        builder: (context, landmarks, _) {
          // update metrics service
          MetricsService.processLandmarks(landmarks);
          return Stack(
            children: [
              CustomPaint(
                painter: FacePainter(landmarks: landmarks),
                child: Container(),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: ValueListenableBuilder<FaceMetrics>(
                  valueListenable: MetricsService.metricsNotifier,
                  builder: (context, m, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EAR: ${m.ear}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('Drowsy: ${m.drowsinessPercent}%', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('Blinks: ${m.blinkCount}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DynamicOverlayPainter extends CustomPainter {
  final List<Offset> landmarks; // normalized (0..1)

  _DynamicOverlayPainter({required this.landmarks});

  @override
  void paint(Canvas canvas, Size size) {
    final paintPoint = Paint()
      ..color = Colors.lightGreenAccent.withOpacity(0.95)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw facial landmarks as small circles
    for (final p in landmarks) {
      final dx = (p.dx.clamp(0.0, 1.0)) * size.width;
      final dy = (p.dy.clamp(0.0, 1.0)) * size.height;
      canvas.drawCircle(Offset(dx, dy), 2.5, paintPoint);
    }

    // If no landmarks, draw a subtle guide
    if (landmarks.isEmpty) {
      final w = size.width * 0.6;
      final h = size.height * 0.2;
      final rect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.4),
          width: w,
          height: h);
      canvas.drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicOverlayPainter oldDelegate) => oldDelegate.landmarks != landmarks;
}
