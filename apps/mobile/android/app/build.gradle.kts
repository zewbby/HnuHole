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
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Opt-in CI test identity. Production signing is configured separately.
    val testSigningNames = listOf("HNUHOLE_TEST_KEYSTORE", "HNUHOLE_TEST_KEY_ALIAS", "HNUHOLE_TEST_STORE_PASSWORD", "HNUHOLE_TEST_KEY_PASSWORD")
    val testSigningValues = testSigningNames.map { System.getenv(it) }
    require(testSigningValues.all { it == null } || testSigningValues.all { !it.isNullOrBlank() }) {
        "All four prerelease test signing inputs are required"
    }
    val testSigning = if (testSigningValues.all { it != null }) {
        signingConfigs.create("prereleaseTest") {
            storeFile = file(testSigningValues[0]!!)
            keyAlias = testSigningValues[1]
            storePassword = testSigningValues[2]
            keyPassword = testSigningValues[3]
        }
    } else null

    // Explicit device preparation only: same authentication identity, owned key,
    // and no historical debug Passkey diagnostic/DAL manifest declarations.
    val deviceProfileValue = System.getenv("HNUHOLE_PRERELEASE_DEVICE")
    require(deviceProfileValue == null || deviceProfileValue == "1") {
        "HNUHOLE_PRERELEASE_DEVICE must be unset or 1"
    }
    val deviceProfile = deviceProfileValue == "1"
    require(!deviceProfile || testSigning != null) {
        "The prerelease device profile requires an explicit test signing identity"
    }
    if (deviceProfile) {
        sourceSets.getByName("debug").manifest.srcFile("src/prereleaseDevice/AndroidManifest.xml")
    }

    buildTypes {
        debug {
            // P1 uses its own durable fixture data, separate from the UI preview.
            val dmText = System.getenv("HNUHOLE_DM_TEXT") == "1"
            val dmChat = System.getenv("HNUHOLE_DM_CHAT") == "1"
            val dmRecovery = System.getenv("HNUHOLE_DM_RECOVERY") == "1"
            val identityAvatar = System.getenv("HNUHOLE_IDENTITY_AVATAR") == "1"
            require(listOf(dmText,dmChat,dmRecovery,identityAvatar,System.getenv("HNUHOLE_DM_PREVIEW") == "1",providers.gradleProperty("hnuholeCommentsValidation").orNull == "true").count { it } <= 1) {
                "Choose one isolated DM package"
            }
            if (dmChat) applicationIdSuffix = ".dmchat"
            if (dmRecovery) applicationIdSuffix = ".dmrecovery"
            if (identityAvatar) applicationIdSuffix = ".identityavatar"
            require(!dmText || System.getenv("HNUHOLE_DM_PREVIEW") != "1") {
                "Choose either DM text integration or the UI preview"
            }
            if (dmText) applicationIdSuffix = ".dmtext"
            // Isolated, memory-only DM preview. Never replaces the daily app.
            if (System.getenv("HNUHOLE_DM_PREVIEW") == "1") {
                applicationIdSuffix = ".dmpreview"
            }
            // Explicit owned acceptance install; ordinary debug/release IDs stay
            // unchanged and existing user data is never reused by this fixture.
            if (providers.gradleProperty("hnuholeCommentsValidation").orNull == "true") {
                applicationIdSuffix = ".commentsvalidation"
            }
            if (deviceProfile) signingConfig = testSigning
        }
        release {
            // Configure an explicit release signing identity before distribution.
            if (testSigning != null) signingConfig = testSigning
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
