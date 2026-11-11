buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath("com.android.tools.build:gradle:" + (project.findProperty("flutterTrueTimeAgpVersion") ?: "8.11.1"))
    }
}
plugins { id("com.android.library") }
group = "dev.pschkllr.flutter_true_time"
version = "0.1.0-dev.1"
allprojects { repositories { google(); mavenCentral() } }
android {
    namespace = "dev.pschkllr.flutter_true_time"
    compileSdk = 36
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
