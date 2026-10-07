// Root Gradle build file for the Android part of the Flutter app.
//
// Structure and APIs mirror the Flutter 3.47 template (Kotlin DSL, the
// `layout.buildDirectory` API - `Project.buildDir` was removed in Gradle 9).
// The Android build output is redirected next to the project root so that
// `flutter build apk` and `flutter clean` behave predictably.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
