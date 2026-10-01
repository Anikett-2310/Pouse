import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.pouse.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pouse.app"
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

    val isProductionReleaseRequested = (project.hasProperty("productionRelease") && project.property("productionRelease").toString().toBoolean()) ||
        (project.hasProperty("releaseProduction") && project.property("releaseProduction").toString().toBoolean()) ||
        System.getenv("POUSE_PRODUCTION_RELEASE")?.toBoolean() == true ||
        System.getenv("RELEASE_PRODUCTION")?.toBoolean() == true

    signingConfigs {
        create("release") {
            val keyAliasProp = keystoreProperties.getProperty("keyAlias")
            val keyPasswordProp = keystoreProperties.getProperty("keyPassword")
            val storeFileProp = keystoreProperties.getProperty("storeFile")
            val storePasswordProp = keystoreProperties.getProperty("storePassword")

            val storeFileObj = if (!storeFileProp.isNullOrEmpty()) {
                val candidate = file(storeFileProp)
                if (candidate.isAbsolute) candidate else rootProject.file(storeFileProp)
            } else null

            val isConfigured = !keyAliasProp.isNullOrEmpty() &&
                !keyPasswordProp.isNullOrEmpty() &&
                !storePasswordProp.isNullOrEmpty() &&
                storeFileObj != null && storeFileObj.exists()

            if (isConfigured) {
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
                storeFile = storeFileObj
                storePassword = storePasswordProp
            } else if (isProductionReleaseRequested) {
                throw org.gradle.api.GradleException(
                    """
                    ================================================================================
                    PRODUCTION RELEASE SIGNING FAILED:
                    Production release mode was explicitly requested (-PproductionRelease=true or
                    RELEASE_PRODUCTION=true), but valid release signing credentials were not found!

                    Missing or invalid prerequisites:
                    - key.properties present: ${keystorePropertiesFile.exists()}
                    - storeFile valid: ${storeFileObj?.exists() ?: false}
                    - keyAlias configured: ${!keyAliasProp.isNullOrEmpty()}

                    Please copy key.properties.example to key.properties, fill in your production
                    keystore credentials, and ensure the keystore file exists.
                    ================================================================================
                    """.trimIndent()
                )
            } else {
                // Development / CI fallback: use debug keystore when key.properties is not supplied
                logger.warn("WARNING: Building release variant with debug signing keys. Set -PproductionRelease=true or RELEASE_PRODUCTION=true to enforce production release signing.")
                val debugConfig = getByName("debug")
                keyAlias = debugConfig.keyAlias
                keyPassword = debugConfig.keyPassword
                storeFile = debugConfig.storeFile
                storePassword = debugConfig.storePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    androidResources {
        noCompress += "task"
    }
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
