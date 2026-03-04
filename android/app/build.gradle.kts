plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

android {
    namespace = "com.example.car_listing_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.car_listing_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signing setup:
    // - Default: release uses debug signing (local/dev friendly).
    // - CI/Store: provide `signing.properties` at repo root to enable real release signing.
    //
    // signing.properties format:
    //   STORE_FILE=/path/to/keystore.jks
    //   STORE_PASSWORD=...
    //   KEY_ALIAS=...
    //   KEY_PASSWORD=...
    val signingProps = Properties()
    val signingPropsFile = rootProject.file("signing.properties")
    if (signingPropsFile.exists()) {
        signingPropsFile.inputStream().use { signingProps.load(it) }
    }

    signingConfigs {
        create("releaseConfig") {
            val storeFilePath = signingProps.getProperty("STORE_FILE")?.trim().orEmpty()
            val storePasswordValue = signingProps.getProperty("STORE_PASSWORD")?.trim().orEmpty()
            val keyAliasValue = signingProps.getProperty("KEY_ALIAS")?.trim().orEmpty()
            val keyPasswordValue = signingProps.getProperty("KEY_PASSWORD")?.trim().orEmpty()

            if (
                storeFilePath.isNotEmpty() &&
                storePasswordValue.isNotEmpty() &&
                keyAliasValue.isNotEmpty() &&
                keyPasswordValue.isNotEmpty()
            ) {
                storeFile = file(storeFilePath)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            val hasReleaseSigning =
                (signingProps.getProperty("STORE_FILE")?.trim().orEmpty().isNotEmpty()) &&
                (signingProps.getProperty("STORE_PASSWORD")?.trim().orEmpty().isNotEmpty()) &&
                (signingProps.getProperty("KEY_ALIAS")?.trim().orEmpty().isNotEmpty()) &&
                (signingProps.getProperty("KEY_PASSWORD")?.trim().orEmpty().isNotEmpty())

            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("releaseConfig")
            } else {
                // Allows `flutter run --release` without any signing setup.
                signingConfigs.getByName("debug")
            }
        }
    }

    // Product flavors for dev/stage/prod
    flavorDimensions += listOf("env")
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("stage") {
            dimension = "env"
            applicationIdSuffix = ".stage"
            versionNameSuffix = "-stage"
        }
        create("prod") {
            dimension = "env"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
