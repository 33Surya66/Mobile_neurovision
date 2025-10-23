# TFLite / OpenCV integration notes

This document collects recommended approaches for adding on-device inference (blink detection, gaze estimation, pupil tracking) to the Flutter skeleton in this repo.

Recommended packages
- tflite_flutter: Flutter bindings for TensorFlow Lite (fast, supports NNAPI/Metal delegates).  
- tflite_flutter_helper: Image processing helpers and tensor conversions.  
- opencv (native): Use platform channels or pre-built plugins if you need OpenCV image processing routines.  

Integration strategy
1. Keep preprocessing lightweight: crop ROI around eyes using a cheap face detection model or simple heuristics.  
2. Use frame skipping and lower resolution (we already sample every Nth frame).  
3. Prefer quantized TFLite models (uint8/int8) for speed and smaller binaries.  
4. Use delegates where available (NNAPI on Android, Metal on iOS).  

Where to plug code
- `lib/screens/home_screen.dart`: current placeholder that receives camera frames. Replace the placeholder delay with a call into a `FrameAnalyzer` service that converts CameraImage to input tensor and runs inference.  

Example snippet (conceptual)
```dart
// initialize interpreter
final interpreter = await Interpreter.fromAsset('blink_model.tflite');

// convert CameraImage to tensor using tflite_flutter_helper
TensorImage input = _convertCameraImage(cameraImage);
interpreter.run(input.buffer, outputBuffer);
```

Privacy
- Do not store raw frames. Only keep derived metrics (e.g., blinks/min) and allow the user to opt-in to sharing.  

Model suggestions
- Start with a small classifier for blink detection (input: cropped eye patch).  
- Use a compact landmark model for pupil center estimation, or use OpenCV pupil detection with native code for speed.

Further resources
- TFLite documentation and model maker samples.  
- Example Flutter TFLite apps on GitHub.
