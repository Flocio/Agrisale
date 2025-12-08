allprojects {
    repositories {
        // 优先使用官方源，阿里云镜像作为备用
        google()
        mavenCentral()
        // 阿里云镜像作为备用（如果官方源失败）
        maven { 
            setUrl("https://maven.aliyun.com/repository/public")
            isAllowInsecureProtocol = false
        }
        maven { 
            setUrl("https://maven.aliyun.com/repository/google")
            isAllowInsecureProtocol = false
        }
        maven { 
            setUrl("https://maven.aliyun.com/repository/gradle-plugin")
            isAllowInsecureProtocol = false
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
