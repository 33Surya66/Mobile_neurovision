plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mobile_neurovision"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.mobile_neurovision"
        minSdk = flutter.minSdkVersion  // Required for camera and TFLite
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Enable multidex for TFLite
        multiDexEnabled = true
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
