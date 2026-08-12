plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hearthbit.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.hearthbit.relay"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    flavorDimensions += "device"
    productFlavors {
        create("tv") {
            dimension = "device"
            applicationIdSuffix = ".tv"
            buildConfigField("String", "TARGET_KIND", "\"tv\"")
            buildConfigField("boolean", "VEHICLE_GATED", "false")
            resValue("string", "app_name", "HearthBit TV Relay")
        }
        create("automotive") {
            dimension = "device"
            applicationIdSuffix = ".automotive"
            buildConfigField("String", "TARGET_KIND", "\"automotive\"")
            buildConfigField("boolean", "VEHICLE_GATED", "true")
            resValue("string", "app_name", "HearthBit Vehicle Relay")
        }
    }

    sourceSets {
        getByName("main").java.srcDirs(
            "src/main/kotlin",
            "../app/src/main/kotlin/com/hearthbit/app/mesh",
            "../../../vendor/bitchat-android/app/src/main/java/com/bitchat/android/noise/southernstorm",
        )
    }

    buildFeatures {
        buildConfig = true
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.85")
    testImplementation("junit:junit:4.13.2")
}
