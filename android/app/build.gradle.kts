plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.File
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

fun loadSigningProperties(root: org.gradle.api.Project): Pair<Properties, java.io.File?> {
    val props = Properties()
    var loaded: java.io.File? = null
    for (rel in listOf("signing.properties", "android/signing.properties")) {
        val candidate = root.file(rel)
        if (candidate.exists()) {
            candidate.inputStream().use { props.load(it) }
            loaded = candidate
            break
        }
    }
    return props to loaded
}

fun hasCompleteSigningProps(props: Properties): Boolean =
    listOf("STORE_FILE", "STORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD").all {
        props.getProperty(it)?.trim().orEmpty().isNotEmpty()
    }

fun resolveKeystoreFile(root: org.gradle.api.Project, storeFilePath: String): File {
    val fromRoot = root.file(storeFilePath)
    if (fromRoot.exists()) return fromRoot
    val absolute = File(storeFilePath)
    if (absolute.exists()) return absolute
    return fromRoot
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}
val googleMapsApiKey = localProperties.getProperty("GOOGLE_MAPS_API_KEY")?.trim().orEmpty()

// Host for https://<host>/listing/... App Links (match API / share URL host).
val appLinkHost = (
    (project.findProperty("APP_LINK_HOST") as String?)?.trim()
        ?: System.getenv("APP_LINK_HOST")?.trim()
        ?: "carr-5hrm.onrender.com"
)

// F-13: explicit, narrowly-scoped opt-in for an intentionally UNSIGNED release
// artifact (CI test APK only; see codemagic.yaml `android_release_unsigned`).
// It never selects the debug key: the release build is simply left unsigned.
val unsignedReleaseRequested =
    (
        (project.findProperty("CARNET_UNSIGNED_RELEASE") as String?)
            ?: System.getenv("CARNET_UNSIGNED_RELEASE")
        )?.trim().equals("true", ignoreCase = true)

android {
    namespace = "com.carzo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    buildFeatures {
        buildConfig = true
    }

    testOptions {
        // Lets pure-JVM unit tests call android.util.Log (no-op) instead of throwing.
        unitTests.isReturnDefaultValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.carzo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey
        manifestPlaceholders["appLinkHost"] = appLinkHost

        val airbridgeAppName = (
            localProperties.getProperty("AIRBRIDGE_APP_NAME")?.trim()
                ?: System.getenv("AIRBRIDGE_APP_NAME")?.trim().orEmpty()
            )
        val airbridgeToken = (
            localProperties.getProperty("AIRBRIDGE_APP_TOKEN")?.trim()
                ?: System.getenv("AIRBRIDGE_APP_TOKEN")?.trim().orEmpty()
            )
        fun esc(s: String): String = s.replace("\\", "\\\\").replace("\"", "\\\"")
        buildConfigField("String", "AIRBRIDGE_APP_NAME", "\"${esc(airbridgeAppName)}\"")
        buildConfigField("String", "AIRBRIDGE_APP_TOKEN", "\"${esc(airbridgeToken)}\"")

        val abHostBase = airbridgeAppName.trim()
        val hostAbr = if (abHostBase.isNotEmpty()) "$abHostBase.abr.ge" else ""
        val hostAbrio = if (abHostBase.isNotEmpty()) "$abHostBase.airbridge.io" else ""
        manifestPlaceholders["airbridgeHostAbrGe"] = hostAbr.ifEmpty { "phony-abr.invalid" }
        manifestPlaceholders["airbridgeHostAirbridgeIo"] = hostAbrio.ifEmpty { "phony-io.invalid" }
    }

    // Signing setup (F-13):
    // - EVERY release build (any flavor, any assemble/bundle/package/publish task)
    //   requires signing.properties (repo root or android/); otherwise the build
    //   fails (see the taskGraph guard below). Release builds NEVER use the debug key.
    // - Debug/profile builds keep the default debug key.
    // - CARNET_UNSIGNED_RELEASE=true is the only way to build release without
    //   signing; it produces an explicitly UNSIGNED artifact (no signing config).
    //
    // signing.properties format:
    //   STORE_FILE=/path/to/keystore.jks
    //   STORE_PASSWORD=...
    //   KEY_ALIAS=...
    //   KEY_PASSWORD=...
    val (signingProps, _) = loadSigningProperties(rootProject)
    val hasReleaseSigning = hasCompleteSigningProps(signingProps)

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
                storeFile = resolveKeystoreFile(rootProject, storeFilePath)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Never falls back to the debug key. Without real signing the
            // variant is unsigned and the taskGraph guard below fails the build
            // (unless CARNET_UNSIGNED_RELEASE=true explicitly asks for unsigned).
            signingConfig = if (hasReleaseSigning && !unsignedReleaseRequested) {
                signingConfigs.getByName("releaseConfig")
            } else {
                null
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
    applicationId = "com.carnetiq.app"
}
    }
}

// F-13: fail-closed guard. Keyed on the task graph (not on a flavor name): any
// :app task whose name mentions "release" (assemble*/bundle*/package*/sign*/
// publish*/validateSigning*Release, any flavor) needs real signing properties.
gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter {
        it.path.startsWith("${project.path}:") && it.name.contains("release", ignoreCase = true)
    }
    if (releaseTasks.isNotEmpty() && !unsignedReleaseRequested) {
        val (props, _) = loadSigningProperties(rootProject)
        if (!hasCompleteSigningProps(props)) {
            throw GradleException(
                "Release build refused: no release signing configured. Release builds are " +
                    "never signed with the debug key. Provide signing.properties (repo root or " +
                    "android/) with STORE_FILE, STORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD. " +
                    "For an intentionally UNSIGNED CI-only APK set CARNET_UNSIGNED_RELEASE=true."
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // HEIC/HEIF Sell-photo preview fix: bundles its OWN native
    // libheif/libde265 (Android decode independent of BitmapFactory/
    // ImageDecoder, which already fail to decode some real-device HEIF
    // files -- see HeifPreviewDecoder.kt and
    // lib/shared/listings/heic_preview_converter.dart for the full
    // root-cause trail). Pinned to the stable 2.2.1 release (no
    // 3.0.0-alpha).
    implementation("io.github.awxkee:avif-coder:2.2.1")
    // SecureStorageRepair.kt probes EncryptedSharedPreferences the same way
    // flutter_secure_storage does. Pinned to the exact version the plugin
    // (9.2.x) already depends on, so Gradle resolves a single copy and the
    // keyset format/behaviour is identical. Deliberately NOT the newer stable
    // 1.1.0: Gradle would then resolve that for the plugin's own runtime code
    // too, silently changing the production secure-storage path. 1.0.0 is not an
    // option either (it predates the MasterKey API the plugin calls). Upgrade
    // together with flutter_secure_storage, as its own change.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    testImplementation("junit:junit:4.13.2")
}
