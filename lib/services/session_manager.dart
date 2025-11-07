import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'session_service.dart';
import '../models/session.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  
  factory SessionManager() => _instance;
  
  SessionManager._internal();
  
  String? _currentSessionId;
  String? _apiKey;
  
  // Session state
  bool get isActive => _currentSessionId != null;
  String? get currentSessionId => _currentSessionId;
  
  // Initialize with API key (call this at app startup)
  void initialize({required String apiKey}) {
    _apiKey = apiKey;
    ApiService.initialize(apiKey: apiKey);
  }
  
  // Start a new recording session
  Future<Map<String, dynamic>> startSession({
    String? userId,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    if (isActive) {
      await endSession();
    }
    
    try {
      final response = await ApiService.startSession(
        metadata: {
          'user_id': userId,
          'device_id': deviceId,
          'platform': _getPlatform(),
          'app_version': '1.0.0', // TODO: Get from pubspec.yaml
          ...?metadata,
        },
      );
      
      if (!response.success) {
        throw Exception(response.error ?? 'Failed to start session');
      }
      
      // Create and save the session locally
      final now = DateTime.now();
      final session = Session(
        id: response.data['session_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        startTime: now,
        endTime: now, // Set endTime to now initially, will be updated when session ends
        durationInSeconds: 0, // Will be updated when session ends
        averageAttention: 0.0, // Will be updated during the session
        blinkCount: 0, // Will be updated during the session
        userId: userId,
        deviceId: deviceId,
        metadata: metadata,
      );
      
      await SessionService().saveSession(session);
      debugPrint('Started and saved session: ${session.id}');
      
      _currentSessionId = response.data['session_id'];
      return response.data;
    } catch (e) {
      debugPrint('Failed to start session: $e');
      rethrow;
    }
  }
  
  // End the current recording session
  Future<Map<String, dynamic>> endSession() async {
    if (!isActive) return {'status': 'no_active_session'};
    
    try {
      final response = await ApiService.endSession();
      final sessionId = _currentSessionId;
      _currentSessionId = null;
      
      if (!response.success) {
        throw Exception(response.error ?? 'Failed to end session');
      }
      
      // Update the session with end time and save
      if (sessionId != null) {
        try {
          final sessionService = SessionService();
          final sessions = await sessionService.getSessions();
          final session = sessions.firstWhere(
            (s) => s.id == sessionId,
            orElse: () {
              final now = DateTime.now();
              final startTime = now.subtract(const Duration(minutes: 1));
              return Session(
                id: sessionId,
                startTime: startTime,
                endTime: now,
                durationInSeconds: now.difference(startTime).inSeconds,
                averageAttention: 0.0,
                blinkCount: 0,
                metadata: {},
              );
            },
          );
          
          final updatedSession = session.copyWith(
            endTime: DateTime.now(),
            durationInSeconds: DateTime.now().difference(session.startTime).inSeconds,
          );
          
          await sessionService.saveSession(updatedSession);
          debugPrint('Ended and updated session: $sessionId');
        } catch (e) {
          debugPrint('Error updating session: $e');
        }
      }
      
      return response.data;
    } catch (e) {
      debugPrint('Failed to end session: $e');
      rethrow;
    }
  }
  
  // Get session data
  Future<Map<String, dynamic>> getSessionData(String sessionId) async {
    try {
      final response = await ApiService.getSession(sessionId);
      if (!response.success) {
        throw Exception(response.error ?? 'Failed to get session data');
      }
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error getting session data: $e');
      rethrow;
    }
  }
  
  // Helper method to get platform information
  String _getPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
  
  // Clean up resources
  void dispose() {
    if (isActive) {
      endSession().catchError((_) {});
    }
  }
}
