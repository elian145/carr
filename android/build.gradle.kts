import com.android.build.gradle.BaseExtension
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Use the already-installed NDK so plugins (e.g. jni) do not auto-download NDK 28.
val forcedNdkVersion = "27.0.12077973"

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Flutter plugins (e.g. sentry_flutter) may pin Kotlin language 1.x; Kotlin 2.3+ rejects that.
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(KotlinVersion.KOTLIN_2_0)
        }
    }

    // Plugins use flutter.ndkVersion (28.x). Force the installed 27.x after
    // each module evaluates so AGP does not try to download another NDK.
    afterEvaluate {
        (extensions.findByName("android") as? BaseExtension)?.ndkVersion = forcedNdkVersion
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
