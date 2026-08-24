plugins {
    id("com.android.library")
}

android {
    namespace = "com.google.zxing.client.android"
    compileSdk = 36

    defaultConfig {
        minSdk = 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

dependencies {
    implementation("com.google.zxing:core:3.5.0")
    implementation("androidx.appcompat:appcompat:1.4.2")
}
