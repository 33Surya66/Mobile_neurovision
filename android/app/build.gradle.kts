plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mobile_neurovision"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.mobile_neurovision"
        minSdk = flutter.minSdkVersion  // Required for camera and ML Kit
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        
        // Enable multidex for ML Kit
        multiDexEnabled = true
        
        ndk {
            // Filter for architectures supported by ML Kit
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
            buildConfigField("String", "API_BASE_URL", "\"https://neurovision-backend.onrender.com\"")
        }
        getByName("debug") {
            buildConfigField("String", "API_BASE_URL", "\"https://neurovision-backend.onrender.com\"")
        }
    }
}

flutter {
    source = "../.."
}
