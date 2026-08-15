import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val releaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val hasReleaseSigning = if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
    val missingKeys = releaseSigningKeys.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
    require(missingKeys.isEmpty()) {
        "android/key.properties is missing: ${missingKeys.joinToString()}"
    }
    true
} else {
    logger.warn(
        "HearthBit release signing is not configured; using the debug key for local/CI builds only."
    )
    false
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val ciBuild = System.getenv("CI")?.equals("true", ignoreCase = true) == true
require(hasReleaseSigning || !releaseRequested || ciBuild) {
    "Release builds require android/key.properties. Debug signing is allowed only in CI."
}

android {
    namespace = "com.hearthbit.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    sourceSets {
        getByName("main").java.srcDir(
            "../../../vendor/bitchat-android/app/src/main/java/com/bitchat/android/noise/southernstorm"
        )
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hearthbit.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile")
                )
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.crypto.tink:tink-android:1.23.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.85.2")
    implementation("com.google.android.gms:play-services-nearby:19.3.0")
    implementation("com.google.android.gms:play-services-base:18.5.0")
    implementation("org.meshtastic:protobufs:2.7.26")
    testImplementation("junit:junit:4.13.2")
}
