allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Harmonisation des modules des plugins Flutter : compileSdk 36 minimum (exigé par androidx.core / flutter_plugin_android_lifecycle,
// file_picker…) et compilation Java 17 minimum (certains plugins sont encore en Java 8).
//
// IMPORTANT : ce bloc doit rester AVANT `evaluationDependsOn(":app")` ci-dessous. Une fois un sous-projet évalué,
// `afterEvaluate` est interdit (« Cannot run Project.afterEvaluate(Action) when the project is already evaluated ») ;
// on enregistre donc le rappel pendant l'évaluation du projet racine, avant qu'aucun module ne soit évalué, et on
// n'enregistre rien pour un module déjà évalué.
val minCompileSdk = 36

fun Project.harmonizeAndroidModule() {
    val android = extensions.findByName("android") ?: return
    // compileSdk : on ne fait que remonter la valeur, jamais la baisser.
    val current = runCatching {
        val v = android.javaClass.getMethod("getCompileSdkVersion").invoke(android) as? String
        v?.substringAfter("android-")?.substringBefore(".")?.toIntOrNull()
    }.getOrNull() ?: 0
    if (current < minCompileSdk) {
        val setters = listOf("setCompileSdk" to Int::class.javaObjectType, "setCompileSdkVersion" to Int::class.javaPrimitiveType!!)
        for ((name, type) in setters) {
            val ok = runCatching { android.javaClass.getMethod(name, type).invoke(android, minCompileSdk); true }.getOrDefault(false)
            if (ok) break
        }
    }
    // Java : au moins 17.
    runCatching {
        val options = android.javaClass.getMethod("getCompileOptions").invoke(android)
        val getSource = options.javaClass.getMethod("getSourceCompatibility")
        val source = getSource.invoke(options) as JavaVersion
        if (source < JavaVersion.VERSION_17) {
            options.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(options, JavaVersion.VERSION_17)
            options.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(options, JavaVersion.VERSION_17)
        }
    }
}

subprojects {
    if (name != "app") {
        if (state.executed) {
            // Déjà évalué : rien ne peut plus être modifié proprement (le module a été traité par un autre mécanisme).
        } else {
            afterEvaluate { harmonizeAndroidModule() }
        }
    }
}

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
