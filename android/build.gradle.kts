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
// Some Flutter plugins still pin an old compileSdk (e.g. geocoding_android→33,
// file_picker→34), which breaks against AndroidX libs that now require 34/36.
// Force every Android subproject to compile against the app's compileSdk (36).
// Registered BEFORE evaluationDependsOn(":app") so the afterEvaluate hooks are
// in place before any subproject is forced to evaluate.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            if (ext is com.android.build.gradle.BaseExtension) {
                val current = ext.compileSdkVersion
                    ?.removePrefix("android-")
                    ?.toIntOrNull()
                if (current == null || current < 36) {
                    ext.compileSdkVersion(36)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
