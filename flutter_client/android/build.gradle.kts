import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension
import org.gradle.kotlin.dsl.configure
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        // JitPack（flutter_webrtc 依赖 com.github.davidliu:audioswitch 等）。
        // 必须限定 group 且置于镜像之前：国内镜像会先代理到 JitPack 的 POM，
        // 但 JitPack 按需构建 AAR，镜像短时间内对 AAR 返回 404，Gradle 一旦从
        // 镜像拿到 POM 就不会再回退到 jitpack.io 取 AAR，导致 ArtifactNotFoundException。
        maven {
            url = uri("https://jitpack.io")
            content {
                includeGroupByRegex("com\\.github\\..*")
                includeGroupByRegex("com\\.gitlab\\..*")
            }
        }
        // 阿里云镜像
        maven { url = uri("https://maven.aliyun.com/repository/public/") }
        maven { url = uri("https://maven.aliyun.com/repository/google/") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin/") }
        // 华为云镜像
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        // 腾讯云镜像
        maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
        // 保留原始仓库作为备用
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
    configurations.configureEach {
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.journeyapps:zxing-android-embedded"))
                .using(project(":zxing_android_embedded_patched"))
                .because("Avoid OrientationEventListener sensor access for app store compliance")
        }
    }
}

subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<ApplicationExtension> {
            ndkVersion = "28.2.13676358"
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            ndkVersion = "28.2.13676358"
            if (project.name == "qr_code_scanner") {
                namespace = "net.touchcapture.qr.flutterqr"
            }
        }
    }

    if (project.name == "qr_code_scanner") {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_1_8)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
