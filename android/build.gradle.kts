allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Configure Java toolchain to use Java 17 for all projects
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            tasks.withType<JavaCompile>().configureEach {
                options.compilerArgs.addAll(listOf("-Xlint:-options"))
            }
        }
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
