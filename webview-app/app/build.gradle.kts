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
        versionCode = 1
        versionName = "1.0"
        // Default server URL (tunnel badle to app ki setting se badlo)
        buildConfigField("String", "DEFAULT_BASE_URL",
            "\"https://bookstore-middle-doe-lanka.trycloudflare.com\"")
    }
    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
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
