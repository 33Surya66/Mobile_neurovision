import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/face_detection_service.dart';

// Disease monitoring settings model
class DiseaseMonitoringSettings {
  // Epilepsy settings
  bool monitorEpilepsy;
  double seizureSensitivity; // 0.0 to 1.0
  String emergencyContact;
  bool sendAlerts;

  // Parkinson's settings
  bool monitorParkinsons;
  double tremorSensitivity; // 0.0 to 1.0
  bool trackMovement;

  // General health settings
  bool monitorHeartRate;
  bool monitorStress;
  int alertThreshold; // 1-10

  DiseaseMonitoringSettings({
    this.monitorEpilepsy = false,
    this.seizureSensitivity = 0.7,
    this.emergencyContact = '',
    this.sendAlerts = true,
    this.monitorParkinsons = false,
    this.tremorSensitivity = 0.5,
    this.trackMovement = true,
    this.monitorHeartRate = false,
    this.monitorStress = false,
    this.alertThreshold = 7,
  });

  // Convert to/from JSON for storage
  Map<String, dynamic> toJson() => {
    'monitorEpilepsy': monitorEpilepsy,
    'seizureSensitivity': seizureSensitivity,
    'emergencyContact': emergencyContact,
    'sendAlerts': sendAlerts,
    'monitorParkinsons': monitorParkinsons,
    'tremorSensitivity': tremorSensitivity,
    'trackMovement': trackMovement,
    'monitorHeartRate': monitorHeartRate,
    'monitorStress': monitorStress,
    'alertThreshold': alertThreshold,
  };

  factory DiseaseMonitoringSettings.fromJson(Map<String, dynamic> json) => DiseaseMonitoringSettings(
    monitorEpilepsy: json['monitorEpilepsy'] ?? false,
    seizureSensitivity: (json['seizureSensitivity'] ?? 0.7).toDouble(),
    emergencyContact: json['emergencyContact'] ?? '',
    sendAlerts: json['sendAlerts'] ?? true,
    monitorParkinsons: json['monitorParkinsons'] ?? false,
    tremorSensitivity: (json['tremorSensitivity'] ?? 0.5).toDouble(),
    trackMovement: json['trackMovement'] ?? true,
    monitorHeartRate: json['monitorHeartRate'] ?? false,
    monitorStress: json['monitorStress'] ?? false,
    alertThreshold: json['alertThreshold'] ?? 7,
  );
}

class SettingsPage extends StatefulWidget {
  final bool useBackend;
  final int frameSkip;
  const SettingsPage({Key? key, required this.useBackend, required this.frameSkip}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _useBackend;
  late int _frameSkip;
  late TextEditingController _backendController;

  // Disease monitoring settings state
  late DiseaseMonitoringSettings _diseaseSettings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _useBackend = widget.useBackend;
    _frameSkip = widget.frameSkip;
    _backendController = TextEditingController(text: FaceDetectionService.backendUrl);
    _diseaseSettings = DiseaseMonitoringSettings();
    _loadDiseaseSettings();
  }

  @override
  void dispose() {
    _backendController.dispose();
    super.dispose();
  }

  void _saveAndExit() {
    final result = {
      'useBackend': _useBackend,
      'frameSkip': _frameSkip,
      'backendUrl': _backendController.text,
    };
    Navigator.of(context).pop(result);
  }


  Future<void> _loadDiseaseSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('disease_monitoring_settings');
    
    if (mounted) {
      setState(() {
        if (settingsJson != null) {
          try {
            // Parse the JSON string to a Map
            final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(
              Map<dynamic, dynamic>.from(
                json.decode(settingsJson) as Map
              )
            );
            _diseaseSettings = DiseaseMonitoringSettings.fromJson(jsonMap);
          } catch (e) {
            debugPrint('Error parsing disease settings: $e');
            _diseaseSettings = DiseaseMonitoringSettings();
          }
        } else {
          _diseaseSettings = DiseaseMonitoringSettings();
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDiseaseSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'disease_monitoring_settings', 
        json.encode(_diseaseSettings.toJson())
      );
    } catch (e) {
      debugPrint('Error saving disease settings: $e');
      // Optionally show an error message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings')),
        );
      }
    }
  }

  Widget _buildDiseaseMonitoringSection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ExpansionTile(
      title: const Text('Disease Monitoring', style: TextStyle(fontWeight: FontWeight.bold)),
      initiallyExpanded: true,
      children: [
        // Epilepsy Settings
        _buildSectionHeader('Epilepsy Monitoring', Icons.medical_services),
        SwitchListTile(
          title: const Text('Enable Epilepsy Monitoring'),
          value: _diseaseSettings.monitorEpilepsy,
          onChanged: (value) => setState(() => _diseaseSettings.monitorEpilepsy = value),
        ),
        if (_diseaseSettings.monitorEpilepsy) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seizure Detection Sensitivity: ${(_diseaseSettings.seizureSensitivity * 100).toInt()}%'),
                Slider(
                  value: _diseaseSettings.seizureSensitivity,
                  onChanged: (value) => setState(() => _diseaseSettings.seizureSensitivity = value),
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Emergency Contact',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: _diseaseSettings.emergencyContact),
                  onChanged: (value) => _diseaseSettings.emergencyContact = value,
                ),
                SwitchListTile(
                  title: const Text('Send Emergency Alerts'),
                  value: _diseaseSettings.sendAlerts,
                  onChanged: (value) => setState(() => _diseaseSettings.sendAlerts = value),
                ),
              ],
            ),
          ),
        ],
        
        const Divider(),
        
        // Parkinson's Settings
        _buildSectionHeader('Parkinson\'s Monitoring', Icons.accessibility_new),
        SwitchListTile(
          title: const Text('Enable Parkinson\'s Monitoring'),
          value: _diseaseSettings.monitorParkinsons,
          onChanged: (value) => setState(() => _diseaseSettings.monitorParkinsons = value),
        ),
        if (_diseaseSettings.monitorParkinsons) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tremor Sensitivity: ${(_diseaseSettings.tremorSensitivity * 100).toInt()}%'),
                Slider(
                  value: _diseaseSettings.tremorSensitivity,
                  onChanged: (value) => setState(() => _diseaseSettings.tremorSensitivity = value),
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                ),
                SwitchListTile(
                  title: const Text('Track Movement Patterns'),
                  value: _diseaseSettings.trackMovement,
                  onChanged: (value) => setState(() => _diseaseSettings.trackMovement = value),
                ),
              ],
            ),
          ),
        ],
        
        const Divider(),
        
        // General Health Settings
        _buildSectionHeader('General Health Monitoring', Icons.monitor_heart),
        SwitchListTile(
          title: const Text('Monitor Heart Rate Variability'),
          value: _diseaseSettings.monitorHeartRate,
          onChanged: (value) => setState(() => _diseaseSettings.monitorHeartRate = value),
        ),
        SwitchListTile(
          title: const Text('Monitor Stress Levels'),
          value: _diseaseSettings.monitorStress,
          onChanged: (value) => setState(() => _diseaseSettings.monitorStress = value),
        ),
        if (_diseaseSettings.monitorHeartRate || _diseaseSettings.monitorStress) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alert Threshold: ${_diseaseSettings.alertThreshold}/10'),
                Slider(
                  value: _diseaseSettings.alertThreshold.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '${_diseaseSettings.alertThreshold}',
                  onChanged: (value) => setState(() => _diseaseSettings.alertThreshold = value.toInt()),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveDiseaseSettings();
              _saveAndExit();
            },
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Detection Settings Section
                  _buildSectionHeader('Detection Settings', Icons.settings),
                  SwitchListTile(
                    title: const Text('Use backend for detection'),
                    value: _useBackend,
                    onChanged: (v) => setState(() => _useBackend = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Frame skip (process every Nth frame):'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 6,
                          divisions: 5,
                          value: _frameSkip.toDouble(),
                          label: '$_frameSkip',
                          onChanged: (v) => setState(() => _frameSkip = v.toInt()),
                        ),
                      ),
                      Text('$_frameSkip'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backendController,
                    decoration: const InputDecoration(
                      labelText: 'Backend URL', 
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Disease Monitoring Section
                  _buildDiseaseMonitoringSection(),
                  
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveAndExit, 
                    child: const Text('Save All Settings'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
