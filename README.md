# NeuroVision — Mobile_neurovision

Small Flutter prototype scaffold for NeuroVision: a mobile on-device neuro-tracking app focused on eye-tracking, blink detection and gaze estimation.

This repo currently contains a minimal Flutter app skeleton with:

- Camera preview (front camera) and a simple overlay (`lib/widgets/eyetracking_overlay.dart`).
- Home screen with Start/Stop streaming placeholder (`lib/screens/home_screen.dart`).

What you can do now
- Install Flutter SDK and open this folder in VS Code or Android Studio.
- Run on a physical device (recommended) or emulator. The app requests camera permission and shows a camera preview.

Quick run (Windows PowerShell):

```powershell
# from repo root
cd C:\Users\surya\Downloads\Mobile_neurovision
flutter pub get
flutter run -d <device-id>
```

Notes & next steps
- Frame processing is currently a placeholder in `HomeScreen`; integrate `tflite_flutter` or platform channels to run optimized models with OpenCV/Dlib.
- Prioritize on-device TFLite models for blink detection and gaze estimation. Keep inference lightweight and use frame skipping + ROI cropping to save CPU.
- Add privacy-friendly settings: store only aggregated metrics locally, not raw frames.

Roadmap (short):
1. Implement lightweight on-device blink detector (TFLite).  
2. Add gaze estimation + pupil center tracking.  
3. Small dashboard with historical metrics and alerts.  
4. Improve UI (animations, attractive theme) and add extension for browser.
# Mobile_neurovision