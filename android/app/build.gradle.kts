import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}
val signingStoreFile = keystoreProperties.getProperty("storeFile")
    ?: System.getenv("ANDROID_KEYSTORE_PATH")
val signingStorePassword = keystoreProperties.getProperty("storePassword")
    ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
val signingKeyAlias = keystoreProperties.getProperty("keyAlias")
    ?: System.getenv("ANDROID_KEY_ALIAS")
val signingKeyPassword = keystoreProperties.getProperty("keyPassword")
    ?: System.getenv("ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    signingStoreFile,
    signingStorePassword,
    signingKeyAlias,
    signingKeyPassword,
).all { !it.isNullOrBlank() }
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (isReleaseBuild) {
    check(hasReleaseSigning) {
        "Release signing requires android/key.properties or the ANDROID_KEYSTORE_* environment variables. See docs/releasing.md."
    }
}

android {
    namespace = "dev.leeef.leeef_reader"
    // receive_sharing_intent uses the Android 17/API 37 share contract.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.leeef.leeef_reader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword
                storeFile = file(signingStoreFile!!)
                storePassword = signingStorePassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
