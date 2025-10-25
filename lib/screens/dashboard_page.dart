import 'package:flutter/material.dart';

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
              children: const [
                Expanded(child: _StatCard(title: 'Avg Attention', value: '72%')),
                SizedBox(width: 12),
                Expanded(child: _StatCard(title: 'Avg Drowsiness', value: '18%')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: const [
                  SizedBox(height: 8),
                  _GraphPlaceholder(title: 'Attention (last 5 min)'),
                  SizedBox(height: 12),
                  _GraphPlaceholder(title: 'Blinks / min'),
                  SizedBox(height: 12),
                  _GraphPlaceholder(title: 'Face Present (session)')
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
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
