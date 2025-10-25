import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://neurovision-backend.onrender.com',
  );
  
  static String? _apiKey;
  static String? _sessionId;
  
  static void initialize({String? apiKey}) {
    _apiKey = apiKey;
  }
  
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
  };

  // Session Management
  static Future<Map<String, dynamic>> startSession({Map<String, dynamic>? metadata}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/sessions/start'),
        headers: _headers,
        body: jsonEncode({'metadata': metadata ?? {}}),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _sessionId = data['session_id'];
        return data;
      } else {
        throw Exception('Failed to start session: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error starting session: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> endSession() async {
    if (_sessionId == null) {
      throw Exception('No active session');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/sessions/$_sessionId/end'),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _sessionId = null;
        return data;
      } else {
        throw Exception('Failed to end session: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error ending session: $e');
      rethrow;
    }
  }

  // Face Detection
  static Future<List<Map<String, double>> detectFaces(
    List<int> imageBytes, {
    String? imagePath,
    bool useSession = true,
  }) async {
    try {
      final url = useSession && _sessionId != null
          ? '$_baseUrl/api/sessions/$_sessionId/detect'
          : '$_baseUrl/detect';
      
      var request = http.MultipartRequest('POST', Uri.parse(url));
      
      // Add headers
      _headers.forEach((key, value) {
        request.headers[key] = value;
      });
      
      // Add image file or bytes
      if (imagePath != null) {
        request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      } else {
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'frame.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['landmarks'] == null) {
          return [];
        }
        
        // Convert flat array to list of points
        final List<dynamic> landmarks = data['landmarks'];
        final List<Map<String, double>> points = [];
        
        for (int i = 0; i < landmarks.length; i += 2) {
          points.add({
            'x': landmarks[i].toDouble(),
            'y': landmarks[i + 1].toDouble(),
          });
        }
        
        return points;
      } else {
        throw Exception('Face detection failed: ${response.body}');
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
        Uri.parse('$_baseUrl/api/sessions/$sessionId'),
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
}

// Helper class for media type
class MediaType {
  final String type;
  final String subtype;
  
  const MediaType(this.type, this.subtype);
  
  @override
  String toString() => '$type/$subtype';
}
