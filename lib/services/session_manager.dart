import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

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
      final sessionData = await ApiService.startSession(
        metadata: {
          'user_id': userId,
          'device_id': deviceId,
          'platform': _getPlatform(),
          'app_version': '1.0.0', // TODO: Get from pubspec.yaml
          ...?metadata,
        },
      );
      
      _currentSessionId = sessionData['session_id'];
      return sessionData;
    } catch (e) {
      debugPrint('Failed to start session: $e');
      rethrow;
    }
  }
  
  // End the current recording session
  Future<Map<String, dynamic>> endSession() async {
    if (!isActive) {
      throw Exception('No active session to end');
    }
    
    try {
      final result = await ApiService.endSession();
      _currentSessionId = null;
      return result;
    } catch (e) {
      debugPrint('Failed to end session: $e');
      rethrow;
    }
  }
  
  // Get session data
  Future<Map<String, dynamic>> getSessionData(String sessionId) async {
    return await ApiService.getSessionData(sessionId);
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
