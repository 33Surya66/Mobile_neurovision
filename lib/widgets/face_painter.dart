import 'package:flutter/material.dart';

class FacePainter extends CustomPainter {
  final List<Offset> landmarks; // normalized 0..1
  final bool drawBox;
  final Color pointColor;
  final Color boxColor;

  FacePainter({required this.landmarks, this.drawBox = true, this.pointColor = Colors.lightGreenAccent, this.boxColor = Colors.white70});

  @override
  void paint(Canvas canvas, Size size) {
    final paintPoint = Paint()..color = pointColor.withOpacity(0.95)..style = PaintingStyle.fill;
    final stroke = Paint()..color = boxColor.withOpacity(0.9)..style = PaintingStyle.stroke..strokeWidth = 2;

    if (landmarks.isEmpty) {
      // draw guide
      final w = size.width * 0.6;
      final h = size.height * 0.25;
      final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.4), width: w, height: h);
      canvas.drawRect(rect, stroke);
      return;
    }

    double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in landmarks) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }

    // draw landmarks
    for (final p in landmarks) {
      final dx = (p.dx.clamp(0.0, 1.0)) * size.width;
      final dy = (p.dy.clamp(0.0, 1.0)) * size.height;
      canvas.drawCircle(Offset(dx, dy), 3.0, paintPoint);
    }

    // bounding box
    if (drawBox) {
      final tl = Offset(minX * size.width, minY * size.height);
      final br = Offset(maxX * size.width, maxY * size.height);
      final rect = Rect.fromPoints(tl, br);
      canvas.drawRect(rect.deflate(2.0), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) {
    return oldDelegate.landmarks != landmarks || oldDelegate.drawBox != drawBox;
  }
}
