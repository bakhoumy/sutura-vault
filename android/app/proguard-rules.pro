# Règles R8/ProGuard — SUTURA VAULT (Section 5.1)
-dontwarn com.google.android.play.core.**

# Conservation SQLCipher JNI natif
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.* { *; }
-keep class com.davidmartos96.sqflite_sqlcipher.** { *; }

# Conservation Biométrie & Keystore
-keep class androidx.biometric.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }