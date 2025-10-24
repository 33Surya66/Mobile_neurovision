@echo off
echo Testing NeuroVision Application...

echo.
echo 1. Checking Flutter installation...
flutter doctor

echo.
echo 2. Getting dependencies...
flutter pub get

echo.
echo 3. Analyzing code...
flutter analyze

echo.
echo 4. Running tests...
flutter test

echo.
echo 5. Building for Android...
flutter build apk --debug

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ All tests passed! App is ready for deployment.
    echo.
    echo Next steps:
    echo 1. Run: flutter run (to test on device)
    echo 2. Run: build_apk.bat (to create release APK)
) else (
    echo.
    echo ❌ Some tests failed. Check the output above.
)

pause
