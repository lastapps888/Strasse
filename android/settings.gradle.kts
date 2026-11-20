pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk n'est pas défini dans local.properties (lancez « flutter pub get » ou « flutter build »)." }
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
    // AGP 9.3.1 : version des gabarits de Flutter 3.50 (minimum accepté : 9.1.1).
    id("com.android.application") version "9.3.1" apply false
    // Kotlin 2.4.10 : même version que celle des gabarits Flutter (et donc que celle annoncée par Codemagic).
    // Elle sert aux plugins qui appliquent encore le Kotlin Gradle Plugin (voir android.builtInKotlin dans gradle.properties).
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
}

include(":app")
