// ignore_for_file: prefer_const_constructors

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// A clean, single-file ReportPage implementation.
// Expects a `report` Map with optional keys:
// - summary: { avg_attention, avg_drowsiness }
// - metrics_count: int
// - flags: list
// - recommendations: list
// - ai_analysis: string
// - ai_analysis_error: string
class ReportPage extends StatelessWidget {
  final Map<String, dynamic> report;

  const ReportPage({Key? key, required this.report}) : super(key: key);

  String _formatDouble(dynamic v) {
    if (v == null) return 'N/A';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }

  // Split AI analysis text into numbered/paragraph points for nicer UI.
  List<String> _splitIntoPoints(String text) {
    if (text.trim().isEmpty) return [];
    // Try to split by numbered sections like "1) ... 2) ..." first.
    final numbered = RegExp(r'(?:^|\n)\s*\d+\)');
    if (numbered.hasMatch(text)) {
      // Insert a separator before each numbered marker then split.
      final replaced = text.replaceAllMapped(RegExp(r'(\d+\))'), (m) => '|||${m.group(0)}');
      final parts = replaced.split('|||').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      return parts.map((p) => _stripMarkers(p)).toList();
    }
    // Fallback: split on double newlines (paragraphs).
    return text.split(RegExp(r'\n\s*\n')).map((p) => _stripMarkers(p)).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  }

  String _stripMarkers(String s) {
    // Remove leading numbering like '1)' and common markdown asterisks/bullets.
    var out = s.replaceAll(RegExp(r'^\d+\)\s*'), '');
    out = out.replaceAll(RegExp(r'\*+'), '');
    out = out.replaceAll(RegExp(r'^[-•]\s*'), '');
    return out.trim();
  }

  String _narrative() {
    final summary = report['summary'] as Map<String, dynamic>? ?? {};
    final count = report['metrics_count'] ?? 0;
    final att = (summary['avg_attention'] is num) ? (summary['avg_attention'] as num).toDouble() : double.nan;
    final dro = (summary['avg_drowsiness'] is num) ? (summary['avg_drowsiness'] as num).toDouble() : double.nan;

    final attPhrase = att.isNaN
        ? 'no attention data'
        : (att >= 75 ? 'high attention' : (att >= 50 ? 'moderate attention' : 'low attention'));

    final droPhrase = dro.isNaN
        ? ''
        : (dro >= 70 ? 'clear signs of drowsiness' : (dro >= 40 ? 'occasional drowsiness' : 'generally alert'));

    final connector = droPhrase.isEmpty ? '' : ' with $droPhrase';

    return 'Across $count samples we observed $attPhrase$connector.';
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = report['summary'] as Map<String, dynamic>? ?? {};
    final flags = List.from(report['flags'] as List<dynamic>? ?? []);
    final recs = List.from(report['recommendations'] as List<dynamic>? ?? []);
    final aiAnalysis = report['ai_analysis'] as String?;
    final aiError = report['ai_analysis_error']?.toString();

    final narrative = _narrative();
  final aiPoints = aiAnalysis != null ? _splitIntoPoints(aiAnalysis) : <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Session Report')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Narrative Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(narrative, style: const TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _section(
                'Summary',
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Samples', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('${report['metrics_count'] ?? 0}'),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Avg Attention', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(_formatDouble(summary['avg_attention'])),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Avg Drowsiness', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(_formatDouble(summary['avg_drowsiness'])),
                    ]),
                  ],
                ),
              ),

              _section(
                'Flags',
                flags.isEmpty
                    ? const Text('No flags detected')
                    : Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: flags.map<Widget>((f) {
                          final text = (f is Map && f.containsKey('message')) ? f['message'].toString() : f.toString();
                          final sev = (f is Map && f.containsKey('severity')) ? f['severity'].toString().toLowerCase() : 'info';
                          late final Color bg;
                          if (sev.contains('high') || sev.contains('critical')) {
                            bg = Colors.red.shade300;
                          } else if (sev.contains('medium')) {
                            bg = Colors.orange.shade300;
                          } else {
                            bg = Colors.blueGrey.shade200;
                          }
                          return Chip(label: Text(text), backgroundColor: bg);
                        }).toList(),
                      ),
              ),

              _section(
                'Recommendations',
                recs.isEmpty
                    ? const Text('No recommendations')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: recs.map<Widget>((r) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Row(children: [
                                const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(child: Text(r.toString())),
                              ]),
                            )).toList(),
                      ),
              ),

              _section(
                'AI Analysis',
                aiAnalysis != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            color: Theme.of(context).colorScheme.primary,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.copy, color: Colors.white),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: aiAnalysis));
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied AI analysis')));
                                    },
                                  )
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...aiPoints.asMap().entries.map((entry) {
                            final idx = entry.key + 1;
                            final text = entry.value;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Text(idx.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(text, style: const TextStyle(fontSize: 14)),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      )
                    : (aiError != null
                        ? Text('AI analysis failed: $aiError')
                        : const Text('AI analysis not available.')),
              ),

              const SizedBox(height: 12),

              const SizedBox(height: 20),
              _buildJsonViewer(context, report),

              const SizedBox(height: 20),
              Center(child: ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJsonViewer(BuildContext context, Map<String, dynamic> data) {
    final encoder = JsonEncoder.withIndent('  ');
    final prettyJson = encoder.convert(data);
    
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Formatted'),
              Tab(text: 'Raw JSON'),
            ],
          ),
          SizedBox(
            height: 300,
            child: TabBarView(
              children: [
                // Formatted View
                SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
                  child: _buildJsonTree(data),
                ),
                // Raw JSON View
                SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
                  child: SelectableText(
                    prettyJson,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonTree(dynamic data, {int depth = 0}) {
    if (data is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0) const Text('{'),
          ...data.entries.map<Widget>((e) {
            final valueWidget = e.value is Map || e.value is List
                ? _buildJsonTree(e.value, depth: depth + 1)
                : Text(
                    e.value is String ? '"${e.value}"' : e.value.toString(),
                    style: TextStyle(
                      color: e.value is String ? Colors.green[800] : Colors.purple[800],
                      fontFamily: 'monospace',
                    ),
                  );

            return Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"${e.key}": ',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  valueWidget,
                  if (e.key != data.entries.last.key) const Text(','),
                ],
              ),
            );
          }).toList(),
          if (depth > 0) Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: const Text('}'),
          ),
        ],
      );
    } else if (data is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('['),
          ...data.asMap().entries.map<Widget>((e) {
            final valueWidget = e.value is Map || e.value is List
                ? _buildJsonTree(e.value, depth: depth + 1)
                : Text(
                    e.value is String ? '"${e.value}"' : e.value.toString(),
                    style: TextStyle(
                      color: e.value is String ? Colors.green[800] : Colors.purple[800],
                      fontFamily: 'monospace',
                    ),
                  );

            return Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  valueWidget,
                  if (e.key != data.length - 1) const Text(','),
                ],
              ),
            );
          }).toList(),
          Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: const Text(']'),
          ),
        ],
      );
    }
    return Text(
      data?.toString() ?? 'null',
      style: const TextStyle(fontFamily: 'monospace'),
    );
  }
}
