import java.util.Properties

plugins {
    id("com.android.application")
}

val repositoryRoot = rootProject.file("..")
val generatedCore = repositoryRoot.resolve("native/atarist_core/android/prebuilt")
val privateProperties = Properties().apply {
    val source = rootProject.file("local.properties")
    if (source.isFile) source.inputStream().use(::load)
}

fun quotedBuildValue(name: String): String {
    val value = privateProperties.getProperty(name, "")
        .replace("\\", "\\\\").replace("\"", "\\\"")
    return "\"$value\""
}

val buildAtariCoreArm64 by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the headless Hatari core for Android ARM64"
    workingDir = repositoryRoot
    environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
    commandLine("bash", "native/atarist_core/android/build.sh", "arm64-v8a")
    inputs.files(
        fileTree(repositoryRoot.resolve("native/atarist_core")) {
            exclude("**/build-*/**", "android/prebuilt/**")
        },
        fileTree(repositoryRoot.resolve("vendor/hatari/src")),
    )
    outputs.file(generatedCore.resolve("arm64-v8a/libatarist_core.so"))
}

android {
    namespace = "com.crownparkcomputing.retroatarist"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.crownparkcomputing.retroatarist"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++20", "-fexceptions", "-frtti")
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    buildFeatures { buildConfig = true }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets.named("main") {
        assets.srcDir(repositoryRoot.resolve("native/assets/emutos"))
        assets.srcDir(repositoryRoot.resolve("native/assets/demo"))
        assets.srcDir(repositoryRoot.resolve("native/assets/branding"))
        jniLibs.srcDir(generatedCore)
    }

    buildTypes {
        debug {
            isJniDebuggable = true
            buildConfigField("String", "RETROMEDIA_EMAIL", quotedBuildValue("retromedia.email"))
            buildConfigField("String", "RETROMEDIA_PASSWORD", quotedBuildValue("retromedia.password"))
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            buildConfigField("String", "RETROMEDIA_EMAIL", "\"\"")
            buildConfigField("String", "RETROMEDIA_PASSWORD", "\"\"")
        }
    }

    packaging {
        jniLibs.keepDebugSymbols += "**/libretro_atarist.so"
    }
}

tasks.named("preBuild").configure { dependsOn(buildAtariCoreArm64) }
