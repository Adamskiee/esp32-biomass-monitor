import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
val releaseProperties =
    if (releaseRequested) {
        val propertiesFile = rootProject.file("key.properties")
        require(propertiesFile.isFile) { "Release signing requires android/key.properties" }
        Properties().apply {
            propertiesFile.inputStream().use { load(it) }
            listOf("storeFile", "storePassword", "keyPassword", "keyAlias").forEach { name ->
                require(!getProperty(name).isNullOrBlank()) { "Release signing requires $name in android/key.properties" }
            }
        }
    } else {
        null
    }

android {
    namespace = "com.biomo.biomassmonitor"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.biomo.biomassmonitor"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseProperties != null) {
            create("release") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyPassword = releaseProperties.getProperty("keyPassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}
