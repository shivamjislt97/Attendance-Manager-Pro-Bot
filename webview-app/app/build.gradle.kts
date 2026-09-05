plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.attendance.webapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.attendance.webapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 3
        versionName = "1.2"
        // Default server URL (stable Worker, tunnel badle bhi same rahega)
        buildConfigField("String", "DEFAULT_BASE_URL",
            "\"https://hidden-bush-188f.shivamjislt95288.workers.dev\"")
    }
    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            storeFile = file("../release.jks")
            storePassword = "attendance123"
            keyAlias = "attendance"
            keyPassword = "attendance123"
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
}
