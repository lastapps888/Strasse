import java.util.Properties

plugins {
    id("com.android.application")
    // Plugin Kotlin classique : nécessaire tant que android.builtInKotlin=false (plugins non migrés, ex. flutter_tts).
    // Passage au Kotlin intégré d'AGP 9 : voir android/gradle.properties.
    id("kotlin-android")
    // Le plugin Gradle de Flutter doit être appliqué après ceux d'Android et de Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de production : android/key.properties (voir key.properties.example). Sans lui, la release est signée avec la clé de debug.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "fr.strasse.strasse"
    // API 36 minimum : exigé par flutter_plugin_android_lifecycle et androidx récents.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "fr.strasse.strasse"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
