buildscript {
    val kotlinVersion = "2.1.10" // Define Kotlin version
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:7.3.1") // Android Gradle plugin
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion") // Kotlin Gradle plugin
        classpath("com.google.gms:google-services:4.4.2") // Firebase Gradle plugin
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Custom build directory configuration
val newBuildDir: File = rootProject.layout.buildDirectory.dir("../../build").get().asFile
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: File = newBuildDir.resolve(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}