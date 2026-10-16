plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.hnuhole.image_viewer_component"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.hnuhole.image_viewer_component"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Product support starts at Android 10; legacy storage is out of scope.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "verification"
    productFlavors {
        create("component") {
            dimension = "verification"
            manifestPlaceholders["viewerAppLabel"] = "HnuHole 图片组件"
        }
        create("nativecheck") {
            dimension = "verification"
            applicationIdSuffix = ".nativecheck"
            versionNameSuffix = "-nativecheck"
            manifestPlaceholders["viewerAppLabel"] = "HnuHole 保存平台验证"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Flutter 3.47's nested `assemble` regenerates this file in debug mode, after
// the outer release command has filtered dev plugins. AGP correctly excludes
// integration_test from release dependencies. Remove only its generated block
// immediately before release javac; debug/instrumentation keep registration.
tasks.withType<JavaCompile>().configureEach {
    if (name.matches(Regex("compile.*ReleaseJavaWithJavac"))) {
        doFirst {
            val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
            val text = registrant.readText()
            val devTest = Regex("(?s)    try \\{\\s*flutterEngine\\.getPlugins\\(\\)\\.add\\(new dev\\.flutter\\.plugins\\.integration_test\\.IntegrationTestPlugin\\(\\)\\);\\s*\\} catch \\(Exception e\\) \\{.*?    \\}\\s*")
            registrant.writeText(text.replace(devTest, ""))
        }
    }
}
