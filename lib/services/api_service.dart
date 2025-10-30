import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://neurovision-backend.onrender.com/api',
  );
  
  static String? _apiKey;
  static String? _sessionId;
  static String? _deviceId;
  
  // Getter for base URL
  static String get baseUrl => _baseUrl;
  
  // Getter for current session ID
  static String? get sessionId => _sessionId;
  
  static void initialize({String? apiKey}) {
    _apiKey = apiKey;
  }
  
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
    'X-Device-ID': _deviceId ?? 'unknown',
    'X-App-Version': '1.0.0', // Get from pubspec.yaml in a real app
    'X-Platform': Platform.operatingSystem,
    'X-OS-Version': Platform.operatingSystemVersion,
  };

  // Session Management
  static Future<Map<String, dynamic>> startSession({Map<String, dynamic>? metadata}) async {
    if (_sessionId != null) {
      return {'session_id': _sessionId, 'status': 'existing_session'};
    }
    
    // Generate a unique device ID if not exists
    _deviceId ??= await _getDeviceId();
    
    final Map<String, dynamic> sessionData = {
      'device_id': _deviceId,
      'start_time': DateTime.now().toIso8601String(),
      'metadata': {
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'app_version': '1.0.0', // You might want to get this from pubspec.yaml
        ...?metadata,
      },
    };
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/sessions/start'),
        headers: _headers,
        body: jsonEncode({'metadata': metadata ?? {}}),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _sessionId = data['session_id'];
        debugPrint('Started session: $_sessionId');
        return data;
      } else {
        throw Exception('Failed to start session (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Error starting session: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> endSession() async {
    if (_sessionId == null) {
      return {'status': 'no_active_session'};
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/sessions/$_sessionId/end'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Ended session: $_sessionId');
        _sessionId = null;
        return data;
      } else {
        throw Exception('Failed to end session (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Error ending session: $e');
      rethrow;
    }
  }

  // Face Detection
  static Future<List<Map<String, double>>> detectFaces(
    List<int> imageBytes, {
    String? imagePath,
    bool useSession = true,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final url = useSession && _sessionId != null
          ? '$_baseUrl/sessions/$_sessionId/detect'
          : '$_baseUrl/detect';
      
      var request = http.MultipartRequest('POST', Uri.parse(url));
      
      // Add headers
      final headers = Map<String, String>.from(_headers);
      request.headers.addAll(headers);
      
      debugPrint('Sending request to: $url');
      
      // Add device and session info
      _deviceId ??= await _getDeviceId();
      request.fields['device_id'] = _deviceId!;
      
      if (useSession && _sessionId != null) {
        request.fields['session_id'] = _sessionId!;
      }
      
      // Add metadata if provided
      if (additionalData != null) {
        additionalData.forEach((key, value) {
          if (value != null) {
            request.fields[key] = value.toString();
          }
        });
      }
      
      // Add image file or bytes
      if (imagePath != null) {
        request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      } else {
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'frame_${DateTime.now().millisecondsSinceEpoch}.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }
      
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timed out');
        },
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['landmarks'] == null) {
          debugPrint('No landmarks found in response');
          return [];
        }
        
        // Convert flat array to list of points
        final List<dynamic> landmarks = data['landmarks'];
        final List<Map<String, double>> points = [];
        
        for (int i = 0; i < landmarks.length; i += 2) {
          if (i + 1 < landmarks.length) {
            points.add({
              'x': (landmarks[i] as num).toDouble(),
              'y': (landmarks[i + 1] as num).toDouble(),
            });
          }
        }
        
        debugPrint('Detected ${points.length} landmarks');
        return points;
      } else {
        debugPrint('Face detection failed (${response.statusCode}): ${response.body}');
        throw Exception('Face detection failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Error detecting faces: $e');
      rethrow;
    }
  }
  
  // Get session data
  static Future<Map<String, dynamic>> getSessionData(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/sessions/$sessionId'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get session data: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting session data: $e');
      rethrow;
    }
  }

  // Get session report (aggregated heuristic report)
  static Future<Map<String, dynamic>> getSessionReport(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/sessions/$sessionId/report'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get session report: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting session report: $e');
      rethrow;
    }
  }

  // Post metrics for the current session
  static Future<bool> postMetrics(Map<String, dynamic> metrics) async {
    if (_sessionId == null) return false;
    try {
      final uri = Uri.parse('$_baseUrl/sessions/$_sessionId/metrics');
      final response = await http.post(uri, headers: _headers, body: jsonEncode(metrics));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        debugPrint('Failed to post metrics (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error posting metrics: $e');
      return false;
    }
  }

  // Generate or retrieve a unique device ID
  static Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');
      
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString('device_id', deviceId);
        debugPrint('Generated new device ID: $deviceId');
      } else {
        debugPrint('Using existing device ID: $deviceId');
      }
      
      return deviceId;
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      // Fallback to a random UUID if SharedPreferences fails
      return const Uuid().v4();
    }
  }
}
