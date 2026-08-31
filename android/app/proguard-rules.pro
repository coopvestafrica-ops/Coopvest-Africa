# Add to proguard-rules.pro for Google Sign-In and Firebase

# Google Sign-In
-keepclassmembers class * {
    @com.google.android.gms.common.api.internal.* <methods>;
}
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Firebase Auth
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Keep model classes
-keep class com.coopvestafrica.app.data.models.** { *; }
-keep class com.coopvestafrica.app.data.repositories.** { *; }

# Retrofit
-keepattributes Signature
-keepattributes Exceptions
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
-dontwarn retrofit2.KotlinExtensions
-dontwarn retrofit2.KotlinExtensions$*

# Dio
-dontwarn dio.**
-keep class dio.** { *; }

# JSON Serializable
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Riverpod
-keep class riverpod.** { *; }
-keep class * extends riverpod.StateNotifier { *; }

# Hive
-keep class org.hive.** { *; }
-keep class com.google.gson.** { *; }
-keepclassmembers class * {
    @flutter.HiveDataType *;
}

# Encryption
-keep class encrypt.** { *; }
-keep class javax.crypto.** { *; }

# JWT
-keep class dart_jsonwebtoken.** { *; }

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# ML Kit Barcode Scanning (used by mobile_scanner) — without these rules,
# R8 minification strips the barcode detector and QR scanning silently
# fails in release builds.
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-dontwarn com.google.mlkit.**

# mobile_scanner plugin
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**
