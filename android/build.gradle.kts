// android/build.gradle.kts
//
// QuillCode — Android plugin build (Kotlin Script).
// Compiles libquill_ts.so via CMake + NDK.
// The Rust crate (quill_perf) is compiled by a Gradle task BEFORE CMake runs,
// so the pre-built .a is in place when ninja links quill_ts.so.
//
// RUST SETUP (one-time, on the dev machine):
//   1. Install Rust:  https://rustup.rs
//   2. Run once:
//        rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
//   After that, `flutter run` compiles Rust automatically on every build.

group = "dev.quillcode.quill_code"
version = "1.0"

plugins {
    id("com.android.library")
}

// ── Helper: find cargo executable ─────────────────────────────────────────────
fun findCargo(): String? {
    // 1. Check PATH (works if rustup is installed normally)
    val pathDirs = (System.getenv("PATH") ?: "").split(File.pathSeparator)
    val exeName  = if (org.gradle.internal.os.OperatingSystem.current().isWindows) "cargo.exe" else "cargo"
    for (dir in pathDirs) {
        val f = File(dir, exeName)
        if (f.exists() && f.canExecute()) return f.absolutePath
    }
    // 2. Common rustup install locations
    val home = System.getProperty("user.home") ?: return null
    val candidates = listOf(
        "$home/.cargo/bin/$exeName",                   // Linux / macOS
        "$home\\.cargo\\bin\\$exeName",                // Windows
        "C:\\Users\\${System.getProperty("user.name")}\\.cargo\\bin\\cargo.exe"
    )
    return candidates.firstOrNull { File(it).exists() }
}

// ── NDK path (used to set AR + CC for cross-compilation) ──────────────────────
val ndkDir: String by lazy {
    // android.ndkDirectory is not available in build.gradle.kts at configuration time,
    // so we resolve it from the SDK location + ndkVersion declared in android block.
    val sdkDir = android.sdkDirectory.absolutePath
    val ndkVer = "26.1.10909125"
    "$sdkDir/ndk/$ndkVer"
}

val hostTag: String by lazy {
    val os = org.gradle.internal.os.OperatingSystem.current()
    when {
        os.isWindows -> "windows-x86_64"
        os.isMacOsX  -> "darwin-x86_64"
        else         -> "linux-x86_64"
    }
}

val toolchain: String by lazy { "$ndkDir/toolchains/llvm/prebuilt/$hostTag" }
val api = 21

// ── Rust ABI targets ──────────────────────────────────────────────────────────
data class RustAbi(val rustTarget: String, val androidAbi: String, val ccPrefix: String)

val rustAbis = listOf(
    RustAbi("aarch64-linux-android",   "arm64-v8a",    "aarch64-linux-android$api"),
    RustAbi("armv7-linux-androideabi", "armeabi-v7a",  "armv7a-linux-androideabi$api"),
    RustAbi("x86_64-linux-android",    "x86_64",       "x86_64-linux-android$api"),
)

val rustRoot = file("src/main/rust")

// ── Task: compile Rust for each ABI ───────────────────────────────────────────
val buildRustTasks = rustAbis.map { abi ->
    tasks.register("buildRust_${abi.androidAbi}") {
        group       = "rust"
        description = "Compile libquill_perf.a for ${abi.androidAbi}"

        val outLib = file("${rustRoot}/target/${abi.rustTarget}/release/libquill_perf.a")
        outputs.file(outLib)
        // Inputs: any change in Rust source re-triggers cargo
        inputs.dir(file("${rustRoot}/src"))
        inputs.file(file("${rustRoot}/Cargo.toml"))

        doLast {
            val cargo = findCargo()
                ?: throw GradleException(
                    "cargo not found in PATH. Install Rust: https://rustup.rs\n" +
                    "Then run: rustup target add ${abi.rustTarget}"
                )

            val isWindows = org.gradle.internal.os.OperatingSystem.current().isWindows
            val ext       = if (isWindows) ".cmd" else ""
            val cc        = "$toolchain/bin/${abi.ccPrefix}-clang$ext"
            val ar        = "$toolchain/bin/llvm-ar${if (isWindows) ".exe" else ""}"

            // Validate toolchain files exist
            if (!File(cc).exists()) {
                throw GradleException(
                    "NDK clang not found at: $cc\n" +
                    "Check ndkVersion in build.gradle.kts and that the NDK is installed."
                )
            }

            // Write .cargo/config.toml so cargo knows linker + ar for this target
            val cargoConfig = file("${rustRoot}/.cargo/config.toml")
            cargoConfig.parentFile.mkdirs()
            if (!cargoConfig.exists()) {
                // Write a skeleton; we'll append the target section dynamically
                cargoConfig.writeText("")
            }

            // Per-target env vars (cargo uses these regardless of config.toml)
            val rustTripleUpper = abi.rustTarget.replace("-", "_").uppercase()

            logger.lifecycle("→ cargo build --release --target ${abi.rustTarget}")
            exec {
                commandLine(
                    cargo, "build", "--release",
                    "--target", abi.rustTarget,
                    "--manifest-path", "${rustRoot}/Cargo.toml"
                )
                environment("ANDROID_NDK_HOME", ndkDir)
                environment("AR",               ar)
                environment("AR_${abi.rustTarget.replace("-", "_")}", ar)
                environment("CC_${abi.rustTarget.replace("-", "_")}", cc)
                environment("CARGO_TARGET_${rustTripleUpper}_LINKER", cc)
                // Make sure cargo's own bin is in PATH (in case it wasn't found via PATH)
                val cargoHome = File(cargo).parentFile?.parentFile?.absolutePath
                if (cargoHome != null) {
                    environment("CARGO_HOME", cargoHome)
                    val currentPath = System.getenv("PATH") ?: ""
                    environment("PATH", "${File(cargo).parent}${File.pathSeparator}$currentPath")
                }
            }

            if (!outLib.exists()) {
                throw GradleException("cargo succeeded but ${outLib} not found!")
            }
            logger.lifecycle("✓ ${abi.androidAbi}: ${outLib}")
        }
    }
}

// ── Task: build all ABIs ───────────────────────────────────────────────────────
val buildRustAll = tasks.register("buildRustAll") {
    group       = "rust"
    description = "Compile libquill_perf.a for all Android ABIs"
    dependsOn(buildRustTasks)
}

// ── Hook Rust build into the CMake/NDK pipeline ────────────────────────────────
//
// Android Gradle Plugin creates tasks named:
//   buildCMakeDebug[<abi>]  / buildCMakeRelease[<abi>]
//   externalNativeBuildDebug / externalNativeBuildRelease
//
// We hook AFTER configuration by using afterEvaluate so all tasks exist.
afterEvaluate {
    val abiFilter = setOf("arm64-v8a", "armeabi-v7a", "x86_64")
    rustAbis
        .filter { it.androidAbi in abiFilter }
        .forEach { abi ->
            val rustTask = tasks.named("buildRust_${abi.androidAbi}")
            // Hook into every cmake build task variant for this ABI
            listOf("Debug", "Release").forEach { variant ->
                tasks.matching {
                    it.name.contains("buildCMake${variant}", ignoreCase = true) &&
                    it.name.contains(abi.androidAbi, ignoreCase = true)
                }.configureEach {
                    dependsOn(rustTask)
                }
            }
            // Also hook externalNativeBuild tasks
            tasks.matching {
                it.name.startsWith("externalNativeBuild") &&
                (it.name.contains("Debug") || it.name.contains("Release"))
            }.configureEach {
                dependsOn(rustTask)
            }
        }
}

android {
    namespace  = "dev.quillcode.quill_code"
    compileSdk = 34
    ndkVersion = "26.1.10909125"

    defaultConfig {
        minSdk = 21

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
     /*   cmake {
            path    = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }*/
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
