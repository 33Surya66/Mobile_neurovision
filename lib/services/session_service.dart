import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/session.dart';
import 'api_service.dart';

class SessionService {
  static const String _sessionsKey = 'sessions';
  static final SessionService _instance = SessionService._internal();
  
  factory SessionService() => _instance;
  
  SessionService._internal();

  // Save session to both local storage and backend
  Future<void> saveSession(Session session) async {
    try {
      // Save to local storage
      await _saveToLocal(session);
      
      // Try to sync with backend
      try {
        await ApiService.createSession(session.toMap());
      } catch (e) {
        // If online sync fails, the data is still saved locally
        print('Failed to sync session with backend: $e');
        // TODO: Implement retry mechanism or offline queue
      }
    } catch (e) {
      print('Error saving session: $e');
      rethrow;
    }
  }

  // Get all sessions, try to fetch from backend first, fallback to local
  Future<List<Session>> getSessions() async {
    try {
      // Try to get from backend first
      try {
        final response = await ApiService.getSessions();
        if (response.success && response.data != null) {
          final sessions = (response.data as List)
              .map((json) => Session.fromMap(json))
              .toList();
          
          // Update local storage with server data
          if (sessions.isNotEmpty) {
            await _saveAllToLocal(sessions);
          }
          
          return sessions;
        }
      } catch (e) {
        print('Failed to fetch sessions from backend: $e');
        // Continue to local fallback
      }
      
      // Fallback to local storage
      return _getFromLocal();
    } catch (e) {
      print('Error getting sessions: $e');
      return [];
    }
  }

  // Delete a session by ID
  Future<void> deleteSession(String sessionId) async {
    try {
      // Delete from local storage
      await _deleteFromLocal(sessionId);
      
      // Try to delete from backend
      try {
        await ApiService.deleteSession(sessionId);
      } catch (e) {
        print('Failed to delete session from backend: $e');
        // TODO: Implement retry mechanism
      }
    } catch (e) {
      print('Error deleting session: $e');
      rethrow;
    }
  }

  // Clear all sessions
  Future<void> clearSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionsKey);
      
      // Try to clear from backend
      try {
        // Note: This will only clear local sessions as there's no bulk delete in ApiService
        // You might want to implement a bulk delete in ApiService if needed
        final sessions = await _getFromLocal();
        for (final session in sessions) {
          await ApiService.deleteSession(session.id);
        }
      } catch (e) {
        print('Failed to clear sessions from backend: $e');
      }
    } catch (e) {
      print('Error clearing sessions: $e');
      rethrow;
    }
  }

  // Get session statistics
  Future<Map<String, dynamic>> getSessionStats() async {
    final sessions = await getSessions();
    
    if (sessions.isEmpty) {
      return {
        'totalSessions': 0,
        'totalDuration': 0,
        'avgAttention': 0.0,
        'totalBlinks': 0,
        'sessionsByDay': {},
      };
    }
    
    final totalDuration = sessions.fold<int>(0, (sum, session) => sum + session.durationInSeconds);
    final totalAttention = sessions.fold<double>(0.0, (sum, session) => sum + session.averageAttention);
    final totalBlinks = sessions.fold<int>(0, (sum, session) => sum + session.blinkCount);
    
    // Group sessions by day
    final sessionsByDay = <String, int>{};
    for (final session in sessions) {
      final dateKey = session.formattedDate;
      sessionsByDay[dateKey] = (sessionsByDay[dateKey] ?? 0) + 1;
    }
    
    return {
      'totalSessions': sessions.length,
      'totalDuration': totalDuration,
      'avgAttention': totalAttention / sessions.length,
      'totalBlinks': totalBlinks,
      'avgSessionDuration': totalDuration ~/ sessions.length,
      'sessionsByDay': sessionsByDay,
    };
  }

  // Local storage methods
  Future<void> _saveToLocal(Session session) async {
    final sessions = await _getFromLocal();
    
    // Remove if exists to update
    sessions.removeWhere((s) => s.id == session.id);
    sessions.add(session);
    
    await _saveAllToLocal(sessions);
  }
  
  Future<void> _saveAllToLocal(List<Session> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = sessions.map((s) => s.toMap()).toList();
    await prefs.setString(_sessionsKey, jsonEncode(sessionsJson));
  }
  
  Future<List<Session>> _getFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = prefs.getString(_sessionsKey);
      
      if (sessionsJson == null || sessionsJson.isEmpty) {
        return [];
      }
      
      final List<dynamic> decoded = jsonDecode(sessionsJson);
      return decoded.map((json) => Session.fromMap(json)).toList();
    } catch (e) {
      print('Error reading from local storage: $e');
      return [];
    }
  }
  
  Future<void> _deleteFromLocal(String sessionId) async {
    final sessions = await _getFromLocal();
    sessions.removeWhere((session) => session.id == sessionId);
    await _saveAllToLocal(sessions);
  }
  
  // Debug method to print all sessions
  Future<void> debugPrintSessions() async {
    try {
      final sessions = await _getFromLocal();
      debugPrint('=== Local Sessions (${sessions.length}) ===');
      for (final session in sessions) {
        debugPrint('ID: ${session.id}');
        debugPrint('  Start: ${session.startTime}');
        debugPrint('  End: ${session.endTime}');
        debugPrint('  Duration: ${session.durationInSeconds}s');
      }
      
      // Also try to get from backend
      try {
        final response = await ApiService.getSessions();
        if (response.success && response.data != null) {
          final serverSessions = (response.data as List)
              .map((json) => Session.fromMap(json as Map<String, dynamic>));
          debugPrint('=== Server Sessions (${serverSessions.length}) ===');
          for (final session in serverSessions) {
            debugPrint('ID: ${session.id}');
            debugPrint('  Start: ${session.startTime}');
            debugPrint('  End: ${session.endTime}');
            debugPrint('  Duration: ${session.durationInSeconds}s');
          }
        }
      } catch (e) {
        debugPrint('Error fetching server sessions: $e');
      }
    } catch (e) {
      debugPrint('Error in debugPrintSessions: $e');
    }
  }
  
  // Sync local sessions with backend
  Future<void> syncWithBackend() async {
    try {
      final localSessions = await _getFromLocal();
      
      // Try to fetch from backend
      try {
        final response = await ApiService.getSessions();
        if (response.success && response.data != null) {
          final serverSessions = (response.data as List)
              .map((json) => Session.fromMap(json as Map<String, dynamic>))
              .toList();
          
          // Find sessions that exist locally but not on server
          final localIds = localSessions.map((s) => s.id).toSet();
          final serverIds = serverSessions.map((s) => s.id).toSet();
          final missingOnServer = localIds.difference(serverIds);
          
          // Upload missing sessions
          for (final id in missingOnServer) {
            final session = localSessions.firstWhere((s) => s.id == id);
            await ApiService.createSession(session.toMap());
          }
          
          // Update local storage with merged data
          final mergedSessions = [...localSessions];
          for (final serverSession in serverSessions) {
            if (!localIds.contains(serverSession.id)) {
              mergedSessions.add(serverSession);
            }
          }
          
          await _saveAllToLocal(mergedSessions);
        }
      } catch (e) {
        print('Failed to sync with backend: $e');
        // Continue with local data if sync fails
      }
    } catch (e) {
      print('Error during sync: $e');
      rethrow;
    }
  }
}
