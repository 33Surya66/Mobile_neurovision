import 'package:intl/intl.dart';
import 'dart:convert';

class Session {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int durationInSeconds;
  final double averageAttention;
  final int blinkCount;
  final Map<String, dynamic> metadata;
  final String? userId;
  final String? deviceId;

  Session({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationInSeconds,
    this.averageAttention = 0.0,
    this.blinkCount = 0,
    Map<String, dynamic>? metadata,
    this.userId,
    this.deviceId,
  }) : metadata = metadata ?? {};

  // Convert Session to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'durationInSeconds': durationInSeconds,
      'averageAttention': averageAttention,
      'blinkCount': blinkCount,
      'metadata': metadata,
      'userId': userId,
      'deviceId': deviceId,
    };
  }

  // Create Session from Map
  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: DateTime.parse(map['endTime']),
      durationInSeconds: map['durationInSeconds'],
      averageAttention: (map['averageAttention'] ?? 0.0).toDouble(),
      blinkCount: map['blinkCount'] ?? 0,
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      userId: map['userId'],
      deviceId: map['deviceId'],
    );
  }

  // Convert to JSON string
  String toJson() => json.encode(toMap());

  // Create from JSON string
  factory Session.fromJson(String source) =>
      Session.fromMap(json.decode(source));

  // Create a copy of the session with updated fields
  Session copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    int? durationInSeconds,
    double? averageAttention,
    int? blinkCount,
    Map<String, dynamic>? metadata,
    String? userId,
    String? deviceId,
  }) {
    return Session(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationInSeconds: durationInSeconds ?? this.durationInSeconds,
      averageAttention: averageAttention ?? this.averageAttention,
      blinkCount: blinkCount ?? this.blinkCount,
      metadata: metadata ?? Map.from(this.metadata),
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  // Formatted getters for UI
  String get formattedDate => DateFormat('MMM d, y').format(startTime);
  String get formattedTime => '${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}';
  
  String get formattedDuration {
    final hours = durationInSeconds ~/ 3600;
    final minutes = (durationInSeconds % 3600) ~/ 60;
    final seconds = durationInSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '$seconds s';
    }
  }

  // Attention level indicator
  String get attentionLevel {
    if (averageAttention > 0.7) return 'High';
    if (averageAttention > 0.4) return 'Medium';
    return 'Low';
  }

  // Attention color for UI
  int get attentionColor {
    if (averageAttention > 0.7) return 0xFF4CAF50; // Green
    if (averageAttention > 0.4) return 0xFFFFC107; // Amber
    return 0xFFF44336; // Red
  }
}
