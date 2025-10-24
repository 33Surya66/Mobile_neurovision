#!/bin/bash

echo "Building NeuroVision APK..."

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build APK
echo "Building APK..."
flutter build apk --release

# Check if build was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ APK build successful!"
    echo "📱 APK location: build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    echo "To install on device:"
    echo "adb install build/app/outputs/flutter-apk/app-release.apk"
else
    echo ""
    echo "❌ APK build failed!"
    echo "Check the error messages above."
fi
