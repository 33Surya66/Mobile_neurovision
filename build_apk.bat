@echo off
echo Building NeuroVision APK...

REM Clean previous builds
echo Cleaning previous builds...
flutter clean

REM Get dependencies
echo Getting dependencies...
flutter pub get

REM Build APK
echo Building APK...
flutter build apk --release

REM Check if build was successful
if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ APK build successful!
    echo 📱 APK location: build\app\outputs\flutter-apk\app-release.apk
    echo.
    echo To install on device:
    echo adb install build\app\outputs\flutter-apk\app-release.apk
) else (
    echo.
    echo ❌ APK build failed!
    echo Check the error messages above.
)

pause
