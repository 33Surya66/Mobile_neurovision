import 'package:flutter/material.dart';
import '../services/face_detection_service.dart';

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

  @override
  void initState() {
    super.initState();
    _useBackend = widget.useBackend;
    _frameSkip = widget.frameSkip;
    _backendController = TextEditingController(text: FaceDetectionService.backendUrl);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              decoration: const InputDecoration(labelText: 'Backend URL', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _saveAndExit, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
