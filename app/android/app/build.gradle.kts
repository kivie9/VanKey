import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Khóa ký bản phát hành: đọc từ android/key.properties (KHÔNG commit, đã có trong .gitignore).
// Tạo bằng tao-khoa-ky-android.cmd ở gốc dự án. Mọi bản cài lên máy phải ký cùng một khóa, nếu không Android
// không cho cài đè và người dùng buộc phải gỡ app (gỡ app là mất kho trên máy).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile") != null

android {
    namespace = "com.vankey.vankey"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vankey.vankey"
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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else if (System.getenv("CI") != null) {
                // Trên CI không bao giờ ký bằng khóa debug: mỗi lần chạy CI là một khóa debug mới, bản phát hành
                // sẽ không cài đè được bản cũ.
                throw GradleException("Thiếu android/key.properties: chưa đặt secret khóa ký Android cho CI.")
            } else {
                logger.warn("CẢNH BÁO: chưa có android/key.properties, bản release đang ký bằng khóa DEBUG của máy này.")
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Cùng phiên bản local_auth_android đã kéo về; dùng trực tiếp cho vân tay gắn khóa Keystore (BiometricVault.kt).
    implementation("androidx.biometric:biometric:1.1.0")
}
