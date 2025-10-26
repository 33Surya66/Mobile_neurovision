import 'package:flutter/material.dart';
import '../services/metrics_service.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // First row of metrics
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(
                      title: 'Attention',
                      value: '${m.attentionPercent.toStringAsFixed(1)}%',
                      color: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(
                      title: 'Drowsiness',
                      value: '${m.drowsinessPercent.toStringAsFixed(1)}%',
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Second row of metrics
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(
                      title: 'Cognitive Load',
                      value: '${m.cognitiveLoad.toStringAsFixed(1)}%',
                      color: Colors.purple,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(
                      title: 'Gaze Stability',
                      value: '${m.gazeStability.toStringAsFixed(1)}%',
                      color: Colors.teal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Third row of metrics
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(
                      title: 'Blink Rate',
                      value: '${m.blinkRate.toStringAsFixed(1)}/min',
                      color: Colors.cyan,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(
                      title: 'Facial Symmetry',
                      value: '${m.facialSymmetry.toStringAsFixed(1)}%',
                      color: Colors.pink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const SizedBox(height: 8),
                  SparklineCard(
                    title: 'Attention (recent)',
                    notifier: MetricsService.attentionSeriesNotifier,
                    lineColor: Colors.blue,
                    maxY: 100,
                  ),
                  const SizedBox(height: 12),
                  SparklineCard(
                    title: 'Cognitive Load (recent)',
                    notifier: MetricsService.cognitiveLoadSeriesNotifier,
                    lineColor: Colors.purple,
                    maxY: 100,
                  ),
                  const SizedBox(height: 12),
                  SparklineCard(
                    title: 'Gaze Stability (recent)',
                    notifier: MetricsService.gazeStabilitySeriesNotifier,
                    lineColor: Colors.teal,
                    maxY: 100,
                  ),
                  const SizedBox(height: 12),
                  SparklineCard(
                    title: 'Blink Rate (per min)',
                    notifier: MetricsService.blinkRateSeriesNotifier,
                    lineColor: Colors.cyan,
                    maxY: 60, // Assuming max 60 blinks per minute
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class SparklineCard extends StatelessWidget {
  final String title;
  final ValueNotifier<List<double>> notifier;
  final Color lineColor;
  final double? maxY; // Optional max Y value for scaling
  
  const SparklineCard({
    Key? key, 
    required this.title, 
    required this.notifier, 
    required this.lineColor,
    this.maxY,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF071226),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<List<double>>(
              valueListenable: notifier,
              builder: (context, list, _) {
                return CustomPaint(
                  painter: _SparklinePainter(
                    data: list,
                    color: lineColor,
                    maxY: maxY,
                  ),
                  child: Container(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double? maxY;
  
  _SparklinePainter({
    required this.data, 
    required this.color,
    this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white.withOpacity(0.02);
    canvas.drawRect(Offset.zero & size, bg);

    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (data.isEmpty) return;
    
    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = maxY ?? data.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => 
      oldDelegate.data != data || 
      oldDelegate.color != color ||
      oldDelegate.maxY != maxY;
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    Key? key,
    required this.title,
    required this.value,
    this.color = Colors.blue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2130),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GraphPlaceholder extends StatelessWidget {
  final String title;
  const _GraphPlaceholder({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF071226),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const Expanded(child: Center(child: Icon(Icons.show_chart, color: Colors.white24, size: 56))),
        ],
      ),
    );
  }
}
