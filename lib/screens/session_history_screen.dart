import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import '../services/session_service.dart';
import '../theme/app_colors.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({Key? key}) : super(key: key);

  @override
  _SessionHistoryScreenState createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  late Future<List<Session>> _sessionsFuture;
  late Future<Map<String, dynamic>> _statsFuture;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _sessionsFuture = _sessionService.getSessions();
      _statsFuture = _sessionService.getSessionStats();
    });
  }

  // Debug function to print all sessions
  Future<void> _debugPrintSessions() async {
    await SessionService().debugPrintSessions();
    // Show a snackbar to indicate the action was performed
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check debug console for session details')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _debugPrintSessions,
            tooltip: 'Debug Sessions',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _showClearAllDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSessionList(),
          _buildStatisticsTab(),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return FutureBuilder<List<Session>>(
      future: _sessionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No sessions found'));
        }

        final sessions = snapshot.data!..sort((a, b) => b.startTime.compareTo(a.startTime));
        
        return ListView.builder(
          itemCount: sessions.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            return _buildSessionCard(sessions[index]);
          },
        );
      },
    );
  }

  Widget _buildStatisticsTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final stats = snapshot.data ?? {};
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatCard(
                'Total Sessions',
                '${stats['totalSessions'] ?? 0}',
                Icons.history,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildStatCard(
                'Total Duration',
                '${_formatDuration(stats['totalDuration'] ?? 0)}',
                Icons.timer,
                Colors.green,
              ),
              const SizedBox(height: 12),
              _buildStatCard(
                'Avg. Attention',
                '${((stats['avgAttention'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                Icons.visibility,
                Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildStatCard(
                'Total Blinks',
                '${stats['totalBlinks'] ?? 0}',
                Icons.visibility_off,
                Colors.purple,
              ),
              const SizedBox(height: 24),
              if (stats['sessionsByDay'] != null && (stats['sessionsByDay'] as Map).isNotEmpty)
                _buildSessionsByDayChart(stats['sessionsByDay'] as Map<String, dynamic>),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsByDayChart(Map<String, dynamic> sessionsByDay) {
    final entries = sessionsByDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    final maxCount = sessionsByDay.values.fold(0, (max, e) => e > max ? e : max);
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sessions by Day',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: entries.map((entry) {
                  final height = maxCount > 0 ? (entry.value / maxCount) * 150 : 0;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${entry.value}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: height.toDouble(),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDay(entry.key),
                          style: const TextStyle(fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(Session session) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSessionDetails(session),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    session.formattedDate,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(session.attentionColor).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      session.attentionLevel,
                      style: TextStyle(
                        color: Color(session.attentionColor),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildInfoChip(Icons.timer, session.formattedDuration),
                  const SizedBox(width: 8),
                  _buildInfoChip(Icons.visibility, '${(session.averageAttention * 100).toStringAsFixed(1)}%'),
                  const SizedBox(width: 8),
                  _buildInfoChip(Icons.visibility_off, '${session.blinkCount} blinks'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
          ),
        ],
      ),
    );
  }

  void _showSessionDetails(Session session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Date', session.formattedDate),
              _buildDetailRow('Start Time', DateFormat('h:mm a').format(session.startTime)),
              _buildDetailRow('End Time', DateFormat('h:mm a').format(session.endTime)),
              _buildDetailRow('Duration', session.formattedDuration),
              const Divider(),
              _buildDetailRow('Attention Level', session.attentionLevel),
              _buildDetailRow('Average Attention', '${(session.averageAttention * 100).toStringAsFixed(1)}%'),
              _buildDetailRow('Blink Count', '${session.blinkCount}'),
              if (session.metadata.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'Metadata:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...session.metadata.entries
                    .map((e) => _buildDetailRow(e.key, e.value.toString()))
                    .toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSession(session.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text('Are you sure you want to delete this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _sessionService.deleteSession(sessionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session deleted')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting session: $e')),
          );
        }
      }
    }
  }

  Future<void> _showClearAllDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Sessions'),
        content: const Text('Are you sure you want to delete all sessions? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _sessionService.clearSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All sessions cleared')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error clearing sessions: $e')),
          );
        }
      }
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    
    final parts = <String>[];
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || hours > 0) parts.add('${minutes}m');
    parts.add('${remainingSeconds}s');
    
    return parts.join(' ');
  }
  
  String _formatDay(String dateStr) {
    try {
      final date = DateFormat('MMM d, y').parse(dateStr);
      return DateFormat('MMM d').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}
