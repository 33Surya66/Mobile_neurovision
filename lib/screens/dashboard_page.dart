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
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(title: 'Attention', value: '${m.attentionPercent}%'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<FaceMetrics>(
                    valueListenable: MetricsService.metricsNotifier,
                    builder: (context, m, _) => _StatCard(title: 'Drowsiness', value: '${m.drowsinessPercent}%'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const SizedBox(height: 8),
                  SparklineCard(title: 'Attention (recent)', notifier: MetricsService.attentionSeriesNotifier, lineColor: Colors.deepOrange),
                  const SizedBox(height: 12),
                  SparklineCard(title: 'Drowsiness (recent)', notifier: MetricsService.drowsinessSeriesNotifier, lineColor: Colors.amber),
                  const SizedBox(height: 12),
                  SparklineCard(title: 'Blink Count (cumulative)', notifier: MetricsService.blinkSeriesNotifier, lineColor: Colors.cyan),
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
  const SparklineCard({Key? key, required this.title, required this.notifier, required this.lineColor}) : super(key: key);

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
                  painter: _SparklinePainter(data: list, color: lineColor),
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
  _SparklinePainter({required this.data, required this.color});

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
    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.data != data || oldDelegate.color != color;
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  const _StatCard({Key? key, required this.title, required this.value}) : super(key: key);

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
