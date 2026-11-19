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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// El lint "vital" de release falla con un error interno en algunos plugins
// (p. ej. image_picker_android). No afecta al APK, así que se desactiva.
subprojects {
    tasks.matching { it.name.contains("lintVital") }.configureEach {
        enabled = false
    }
}
