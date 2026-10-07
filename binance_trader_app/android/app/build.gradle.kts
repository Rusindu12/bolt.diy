import java.util.Properties

// App module build file (Kotlin DSL, mirroring the Flutter 3.47 template).
//
// Two deliberate additions to the template:
//   1. `minSdk = 24` - flutter_secure_storage needs the Android Keystore APIs
//      that are guaranteed from API 23, and 24 is Flutter's own minimum.
//   2. Release signing from `android/key.properties` when that file exists,
//      falling back to the debug key so `flutter build apk --release` always
//      produces an installable APK on a fresh checkout / CI runner.
//
// `ndkVersion` is intentionally NOT set: no plugin in this project contains
// native code, and omitting it avoids a ~1 GB NDK download.

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin applies the Kotlin plugin for the app module
    // (Kotlin sources such as MainActivity.kt are compiled without declaring
    // `org.jetbrains.kotlin.android` here, which Flutter 3.47 warns about).
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- optional release keystore ---------------------------------------------
val keystorePropertiesFile = rootProject.file("key.properties")
// NOTE: `Properties()` (imported above) and not `java.util.Properties()`: inside
// a Kotlin DSL script `java` resolves to Gradle's java extension, which makes
// the fully qualified form fail with "Unresolved reference 'util'".
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { stream -> keystoreProperties.load(stream) }
}

android {
    // Change BOTH the namespace and the applicationId (and rename the Kotlin
    // package folder to match) before publishing under your own name.
    namespace = "com.example.binance_trader_app"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.binance_trader_app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Sideloadable, but do not publish an APK signed like this.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
