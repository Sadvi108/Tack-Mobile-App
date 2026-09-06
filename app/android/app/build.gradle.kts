plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release credentials are supplied by the build environment. No password is
// stored in this repository, and a release never falls back to a debug key.
val releaseStore = providers.environmentVariable("TACK_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("TACK_KEYSTORE_PASSWORD").orNull
val releaseAlias = providers.environmentVariable("TACK_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("TACK_KEY_PASSWORD").orNull
val releaseSigningReady = listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword)
    .all { !it.isNullOrBlank() }

android {
    namespace = "com.tack.tack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tack.tack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningReady) signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val packagingRelease = allTasks.any {
        it.project == project && it.name in listOf("assembleRelease", "bundleRelease", "packageRelease")
    }
    if (packagingRelease && !releaseSigningReady) {
        throw GradleException("Release signing is missing. Set TACK_KEYSTORE_PATH, TACK_KEYSTORE_PASSWORD, TACK_KEY_ALIAS and TACK_KEY_PASSWORD in the build environment.")
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
