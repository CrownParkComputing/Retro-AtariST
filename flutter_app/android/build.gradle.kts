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
// Force every Flutter plugin module up to the same compileSdk as the app.
//
// Registered BEFORE the evaluationDependsOn(":app") block below, and that
// ordering is load-bearing: evaluationDependsOn forces the subproject to
// evaluate immediately, after which afterEvaluate throws outright --
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated".
//
// Gradle refuses the build when one module depends on another compiled
// against a newer platform than itself -- here :flutter_plugin_android_lifecycle
// wants 36 while :file_picker ships compiled against 34. Neither is a module
// this project owns, so the fix cannot live in their build files; it has to be
// applied from here.
//
// compileSdk only widens the APIs available at COMPILE time. It does not touch
// targetSdk (runtime behaviour) or minSdk (which devices can install), so
// raising it for a plugin changes nothing about how that plugin behaves.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            val setter = android.javaClass.methods.firstOrNull {
                it.name == "setCompileSdkVersion" && it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.java
            }
            setter?.invoke(android, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
