allprojects {
    repositories {
        maven { setUrl("https://maven.aliyun.com/repository/public") }
        maven { setUrl("https://maven.aliyun.com/repository/google") }
        maven { setUrl("https://maven.aliyun.com/repository/gradle-plugin") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // 为所有 Android 库项目添加 namespace 配置
    plugins.withId("com.android.library") {
        afterEvaluate {
            try {
                val android = project.extensions.getByName("android")
                
                // 尝试从 AndroidManifest.xml 读取 package 属性
                val manifestFiles = listOf(
                    project.file("src/main/AndroidManifest.xml"),
                    project.file("AndroidManifest.xml")
                )
                
                var namespace: String? = null
                for (manifestFile in manifestFiles) {
                    if (manifestFile.exists()) {
                        val manifestContent = manifestFile.readText()
                        val packageMatch = Regex("package=\"([^\"]+)\"").find(manifestContent)
                        if (packageMatch != null) {
                            namespace = packageMatch.groupValues[1]
                            break
                        }
                    }
                }
                
                if (namespace != null) {
                    // 使用反射设置 namespace
                    try {
                        val setNamespaceMethod = android.javaClass.getMethod("setNamespace", String::class.java)
                        setNamespaceMethod.invoke(android, namespace)
                    } catch (e: Exception) {
                        // 如果反射失败，尝试直接设置属性
                        try {
                            val field = android.javaClass.getDeclaredField("namespace")
                            field.isAccessible = true
                            field.set(android, namespace)
                        } catch (e2: Exception) {
                            println("Warning: Could not set namespace for ${project.name}: ${e2.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                println("Warning: Error processing ${project.name}: ${e.message}")
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
