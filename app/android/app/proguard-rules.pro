-keepattributes *Annotation*,InnerClasses,EnclosingMethod,Signature

# Flutter registra plugins y entrypoints desde metadatos/reflexión.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# SQLCipher puede abrir bases mediante factories y JNI.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# Proveedores criptográficos y el motor Noise se seleccionan por nombre.
-keep class org.bouncycastle.jce.provider.BouncyCastleProvider { *; }
-keep class org.bouncycastle.crypto.** { *; }
-keep class com.bitchat.android.noise.southernstorm.** { *; }

# Solo se usa durante la migración conservadora desde security-crypto.
-keep class androidx.security.crypto.** { *; }
