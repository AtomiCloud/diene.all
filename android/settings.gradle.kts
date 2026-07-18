pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    val flutterGradlePlugin = file("$flutterSdkPath/packages/flutter_tools/gradle")
    val writableFlutterGradlePlugin =
        if (flutterGradlePlugin.canWrite()) {
            flutterGradlePlugin
        } else {
            val cacheKey = file(flutterSdkPath).name
            file(".gradle/flutter-plugin-$cacheKey").also { cachedPlugin ->
                if (!cachedPlugin.exists()) {
                    flutterGradlePlugin.copyRecursively(cachedPlugin)
                    // nixpkgs wraps Flutter's Gradle build with a read-only SDK
                    // redirect. The mirror itself is writable, so use upstream's
                    // Kotlin settings file directly instead of that redirect.
                    cachedPlugin.resolve("settings.gradle").delete()
                }
            }
        }

    includeBuild(writableFlutterGradlePlugin.absolutePath)

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
