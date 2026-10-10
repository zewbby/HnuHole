plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.hnuhole.hnuhole_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.hnuhole.hnuhole_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Configure an explicit release signing identity before distribution.
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

// Owned src/debug diagnostic uses the public API already present transitively
// through credentials-play-services-auth. It is not part of release sources.
dependencies {
    // Plugin implementation dependencies already provide the runtime artifacts.
    // Expose only their public types to src/debug, without changing that graph.
    debugCompileOnly("com.google.android.gms:play-services-fido:21.0.0") { isTransitive = false }
    debugCompileOnly("com.google.android.gms:play-services-base:18.5.0") { isTransitive = false }
    debugCompileOnly("com.google.android.gms:play-services-basement:18.5.0") { isTransitive = false }
    debugCompileOnly("com.google.android.gms:play-services-tasks:18.2.0") { isTransitive = false }
}
