// android/build.gradle.kts
//
// QuillCode — Android plugin build (Kotlin Script).
// Compiles libquill_ts.so via CMake + NDK.
// The .so is bundled inside the APK automatically by Gradle —
// no manual step needed after running scripts/fetch_grammars.sh once.

group = "dev.quillcode.quill_code"
version = "1.0"

plugins {
    id("com.android.library")
}

android {
    namespace  = "dev.quillcode.quill_code"
    compileSdk = 34
    ndkVersion = "26.1.10909125"

    defaultConfig {
        minSdk = 21       // Android 5.0+

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                cFlags   += "-std=c11"
                arguments(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_PLATFORM=android-21"
                )
                abiFilters += setOf("arm64-v8a", "armeabi-v7a", "x86_64")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path    = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            externalNativeBuild {
                cmake {
                    arguments("-DCMAKE_BUILD_TYPE=Release")
                }
            }
        }
        debug {
            externalNativeBuild {
                cmake {
                    arguments("-DCMAKE_BUILD_TYPE=Debug")
                }
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}
