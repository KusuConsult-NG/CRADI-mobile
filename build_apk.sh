#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting Release Build for CRADI Mobile..."

# Clean build artifacts
echo "🧹 Cleaning project..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build Release APK for each architecture separately to avoid Memory (OOM) issues
# This system has limited RAM/Swap, so we build one by one.
echo "🏗️ Building Release APK (arm64)..."
flutter build apk --release --no-tree-shake-icons --target-platform android-arm64
mv build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/app-release-arm64.apk

echo "🏗️ Building Release APK (arm)..."
flutter build apk --release --no-tree-shake-icons --target-platform android-arm
mv build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/app-release-arm.apk

echo "🏗️ Building Release APK (x64)..."
flutter build apk --release --no-tree-shake-icons --target-platform android-x64
mv build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/app-release-x64.apk

# Create a symlink or copy one as the main release apk
cp build/app/outputs/flutter-apk/app-release-arm64.apk build/app/outputs/flutter-apk/app-release.apk

echo "✅ Build Complete!"
echo "📍 APK Location: build/app/outputs/flutter-apk/app-release.apk"
