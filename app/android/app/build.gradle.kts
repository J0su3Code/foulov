import java.util.Properties

plugins {
    id("com.android.application")
    // Lit google-services.json (identifiant OAuth « Web » pour la connexion Google). Fichier hors git : voir app/README.md.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé d'envoi Google Play : android/key.properties (hors git), qui pointe vers le fichier .jks rangé hors du dépôt.
// Sans ce fichier (autre machine, intégration continue), la version de publication est signée avec la clé de test.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "org.foulov.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Rappels programmés (flutter_local_notifications) : API java.time sur les anciens Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "org.foulov.app"
        // Version : `version:` de pubspec.yaml (nom + numéro de build, à augmenter à chaque envoi sur Google Play).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("upload") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
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
    // Thème AppCompat de l'activité (requis par local_auth sur Android 8 et antérieurs).
    implementation("androidx.appcompat:appcompat:1.7.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
