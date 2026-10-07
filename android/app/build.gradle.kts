import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.westgatestratagem.climate_app.climate_app"
    compileSdk = 36  // Required by plugins (connectivity_plus, image_picker, etc.)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.westgatestratagem.climate_app.climate_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // currently 24 (Android 7.0)
        targetSdk = 36  // Latest Android SDK
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only define the release signing config when key.properties exists,
        // so debug builds (and CI without the keystore) still configure.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Security: Enable code minification and obfuscation
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            
            // Release builds are signed with the upload key only. Without
            // key.properties the build fails (see verifyReleaseSigning below)
            // instead of silently producing a debug-signed release.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            // Disable minification for debug builds
            isMinifyEnabled = false
        }
    }
}

// Fails any release build (flutter build apk / appbundle, run --release)
// when the release keystore is not configured. Debug and profile builds
// (flutter run) are unaffected.
val hasReleaseKeystore = keystorePropertiesFile.exists()
val verifyReleaseSigning by tasks.registering {
    doFirst {
        if (!hasReleaseKeystore) {
            throw GradleException(
                "Release signing is not configured: android/key.properties is " +
                    "missing. Copy android/key.properties.template to " +
                    "android/key.properties and fill in the upload keystore " +
                    "(storeFile, storePassword, keyAlias, keyPassword). " +
                    "Use a debug build (flutter run) for local testing."
            )
        }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(verifyReleaseSigning)
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
