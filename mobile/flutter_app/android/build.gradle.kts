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

subprojects {
    val configureNamespace = {
        try {
            val android = extensions.findByName("android")
            if (android != null) {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val namespace = getNamespace.invoke(android)
                if (namespace == null) {
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, project.group.toString())
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    plugins.withId("com.android.library") {
        configureNamespace()
    }
    plugins.withId("com.android.application") {
        configureNamespace()
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
