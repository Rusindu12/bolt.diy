// Plugin resolution for the Android build.
//
// `flutter.sdk` is written to `android/local.properties` by the Flutter tool on
// the first `flutter pub get` / `flutter build`.
//
// Versions are the ones Flutter 3.47.x ships in its own template:
//   Gradle 9.3.1  (gradle/wrapper/gradle-wrapper.properties)
//   AGP    9.1.0  (below)
//   Kotlin         (applied by the Flutter Gradle Plugin)
// Keeping these in step with the Flutter release is what makes the Gradle
// plugin, the Android plugin and the Kotlin compiler agree with each other.

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    // No Kotlin plugin declaration: the Flutter Gradle Plugin applies the exact
    // Kotlin version that matches this Flutter release.
}

include(":app")
