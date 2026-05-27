plugins {
   id("com.android.application")
   id("dev.flutter.flutter-gradle-plugin")
}

android {
   namespace = "com.hermesagent.hermes_android"
   compileSdk = 36

   compileOptions {
       sourceCompatibility = JavaVersion.VERSION_17
       targetCompatibility = JavaVersion.VERSION_17
   }

   defaultConfig {
       applicationId = "com.hermesagent.hermes_android"
       minSdk = 24
       targetSdk = 36
       versionCode = 1
       versionName = "0.0.1"
   }

   buildTypes {
       release {
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
