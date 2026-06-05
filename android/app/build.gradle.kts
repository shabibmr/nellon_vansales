plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nellon.vansales.van_sales"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nellon.vansales.van_sales"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// Brand the generated release APK as app-nellon-release.apk.
// AGP 9 removed the variant outputFileName API, so we copy after packaging.
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val releaseDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
            val original = releaseDir.resolve("app-release.apk")
            if (original.exists()) {
                original.copyTo(releaseDir.resolve("app-nellon-release.apk"), overwrite = true)
                // Also place a branded copy alongside Flutter's flutter-apk output.
                val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
                flutterApkDir.mkdirs()
                original.copyTo(flutterApkDir.resolve("app-nellon-release.apk"), overwrite = true)
            }
        }
    }
}
