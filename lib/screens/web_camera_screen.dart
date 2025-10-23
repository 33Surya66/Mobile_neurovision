import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class WebCameraScreen extends StatefulWidget {
  const WebCameraScreen({Key? key}) : super(key: key);

  @override
  State<WebCameraScreen> createState() => _WebCameraScreenState();
}

class _WebCameraScreenState extends State<WebCameraScreen> {
  bool _running = false;

  Future<void> _start() async {
    try {
      await js_util.promiseToFuture(js_util.callMethod(js_util.globalThis, 'startFaceDetection', []));
      setState(() => _running = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start error: $e')));
    }
  }

  void _stop() {
    try {
      js_util.callMethod(js_util.globalThis, 'stopFaceDetection', []);
      setState(() => _running = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stop error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Scaffold(body: Center(child: Text('Web camera screen is only available on web.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Web Camera Test')),
      body: Column(
        children: [
          Expanded(child: Center(child: Text(_running ? 'Running...' : 'Stopped'))),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _running ? null : _start,
                    child: const Text('Start Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _running ? _stop : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('Stop Camera'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
