# Play Core
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# ============================================
# Appwrite SDK
# ============================================
-keep class io.appwrite.** { *; }
-keep class io.appwrite.models.** { *; }
-keep class io.appwrite.services.** { *; }
-dontwarn io.appwrite.**

# ============================================
# Firebase (FCM, Crashlytics, Analytics)
# ============================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }

# ============================================
# Hive Database
# ============================================
-keep class hive.** { *; }
-keep class hive_flutter.** { *; }
-dontwarn hive.**

# Keep Hive TypeAdapters
-keep class * extends hive.TypeAdapter { *; }

# ============================================
# Flutter & Dart
# ============================================
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# ============================================
# Application Models & Data Classes
# ============================================
# Keep all model classes (adjust package name if different)
-keep class com.westgatestratagem.climate_app.climate_app.**.models.** { *; }
-keepclassmembers class com.westgatestratagem.climate_app.climate_app.**.models.** { *; }

# Keep classes with @Keep annotation
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# ============================================
# JSON Serialization
# ============================================
# Gson (if used)
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }

# ============================================
# Security & Biometrics
# ============================================
-keep class androidx.biometric.** { *; }
-keep class androidx.security.crypto.** { *; }

# ============================================
# Crash Reporting & Debugging
# ============================================
# Preserve line numbers for stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep exception classes
-keep public class * extends java.lang.Exception

# ============================================
# Networking
# ============================================
-keepattributes *Annotation*,Signature,Exception

# OkHttp (used by Appwrite)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ============================================
# General Android
# ============================================
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
