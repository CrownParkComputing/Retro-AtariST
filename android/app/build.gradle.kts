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

data class KeystoreConfig(
    val path: String,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

fun resolveKeystore(): KeystoreConfig? {
    val envPath = System.getenv("ANDROID_KEYSTORE_PATH")
    val envStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val envAlias = System.getenv("ANDROID_KEY_ALIAS")
    val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
    if (envPath != null && envStorePassword != null &&
        envAlias != null && envKeyPassword != null
    ) {
        logger.lifecycle("release: using keystore from ANDROID_KEYSTORE_PATH")
        return KeystoreConfig(envPath, envStorePassword, envAlias, envKeyPassword)
    }

    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.isFile) {
        val values = Properties().apply { propertiesFile.inputStream().use(::load) }
        val path = values.getProperty("storeFile")
        val storePassword = values.getProperty("storePassword")
        val alias = values.getProperty("keyAlias")
        val keyPassword = values.getProperty("keyPassword")
        if (path != null && storePassword != null && alias != null && keyPassword != null) {
            logger.lifecycle("release: using ignored local key.properties")
            return KeystoreConfig(path, storePassword, alias, keyPassword)
        }
    }

    logger.warn(
        "release: no upload keystore configured; the release bundle will be unsigned"
    )
    return null
}

val keystoreConfig = resolveKeystore()

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

    signingConfigs {
        create("release") {
            if (keystoreConfig != null) {
                storeFile = file(keystoreConfig.path)
                storePassword = keystoreConfig.storePassword
                keyAlias = keystoreConfig.keyAlias
                keyPassword = keystoreConfig.keyPassword
            }
        }
    }

    buildTypes {
        debug {
            isJniDebuggable = true
            buildConfigField("String", "RETROMEDIA_EMAIL", quotedBuildValue("retromedia.email"))
            buildConfigField("String", "RETROMEDIA_PASSWORD", quotedBuildValue("retromedia.password"))
        }
        release {
            if (keystoreConfig != null) {
                signingConfig = signingConfigs.getByName("release")
            }
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
