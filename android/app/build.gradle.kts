import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.nellon.vansales.van_sales"
    compileSdk = 37
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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
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

// Brand the generated release APK as app-nellon-release.apk.
// AGP 9 removed the variant outputFileName API, so we copy after packaging.
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Release signing is not configured. Copy android/key.properties.example " +
                        "to android/key.properties and generate android/nellon-release.jks. " +
                        "See docs/app_update.md. Phones already running a debug-signed build " +
                        "cannot upgrade onto this keystore — they need a one-time reinstall.",
                )
            }
        }
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
