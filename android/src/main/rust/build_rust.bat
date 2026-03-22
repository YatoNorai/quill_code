@echo off
:: build_rust.bat — compila libquill_perf.a para todos os ABIs Android
:: Pré-requisitos:
::   1. Rust instalado: https://rustup.rs
::   2. Android NDK r26+ instalado via Android Studio
::   3. Targets Rust instalados (este script instala se necessário)
::
:: Uso:
::   android\src\main\rust\build_rust.bat
::   android\src\main\rust\build_rust.bat [NDK_PATH]
::
:: Exemplo:
::   build_rust.bat "C:\Users\Matheus\AppData\Local\Android\Sdk\ndk\26.1.10909125"

setlocal EnableDelayedExpansion

:: ── Detecta NDK ──────────────────────────────────────────────────────────────
if not "%~1"=="" (
    set "NDK=%~1"
) else if defined ANDROID_NDK_HOME (
    set "NDK=%ANDROID_NDK_HOME%"
) else if defined ANDROID_NDK (
    set "NDK=%ANDROID_NDK%"
) else (
    :: Tenta localização padrão do Android Studio
    set "NDK=%LOCALAPPDATA%\Android\Sdk\ndk"
    if exist "!NDK!" (
        :: Pega a versão mais recente
        for /f "delims=" %%d in ('dir /b /ad "!NDK!" 2^>nul') do set "NDK_VER=%%d"
        set "NDK=!NDK!\!NDK_VER!"
    ) else (
        echo ERRO: NDK nao encontrado. Instale via Android Studio ou defina ANDROID_NDK_HOME.
        exit /b 1
    )
)

if not exist "%NDK%" (
    echo ERRO: NDK nao encontrado em: %NDK%
    exit /b 1
)
echo NDK: %NDK%

set "TOOLCHAIN=%NDK%\toolchains\llvm\prebuilt\windows-x86_64"
if not exist "%TOOLCHAIN%" (
    echo ERRO: Toolchain nao encontrado: %TOOLCHAIN%
    exit /b 1
)

:: ── Diretório do Cargo.toml ───────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
set "MANIFEST=%SCRIPT_DIR%Cargo.toml"
if not exist "%MANIFEST%" (
    echo ERRO: Cargo.toml nao encontrado em %SCRIPT_DIR%
    exit /b 1
)

:: ── Verifica cargo ────────────────────────────────────────────────────────────
where cargo >nul 2>&1
if errorlevel 1 (
    echo ERRO: cargo nao encontrado no PATH.
    echo Instale o Rust: https://rustup.rs
    exit /b 1
)

:: ── Instala targets ───────────────────────────────────────────────────────────
echo Instalando targets Rust...
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android

:: ── Define compiladores por ABI ───────────────────────────────────────────────
:: Android NDK r23+ usa clang com suffixo de API level (ex: aarch64-linux-android21-clang)
set "API=21"

set "CC_arm64=%TOOLCHAIN%\bin\aarch64-linux-android%API%-clang.cmd"
set "CC_arm32=%TOOLCHAIN%\bin\armv7a-linux-androideabi%API%-clang.cmd"
set "CC_x86_64=%TOOLCHAIN%\bin\x86_64-linux-android%API%-clang.cmd"
set "CC_x86=%TOOLCHAIN%\bin\i686-linux-android%API%-clang.cmd"
set "AR=%TOOLCHAIN%\bin\llvm-ar.exe"

:: ── Cria .cargo/config.toml para cross-compile ─────────────────────────────
set "CARGO_DIR=%SCRIPT_DIR%.cargo"
if not exist "%CARGO_DIR%" mkdir "%CARGO_DIR%"

:: Substitui backslashes por forward slashes no path (TOML não aceita \)
set "CC_ARM64_FWD=%CC_arm64:\=/%"
set "CC_ARM32_FWD=%CC_arm32:\=/%"
set "CC_X64_FWD=%CC_x86_64:\=/%"
set "CC_X86_FWD=%CC_x86:\=/%"
set "AR_FWD=%AR:\=/%"

(
echo [target.aarch64-linux-android]
echo linker = "%CC_ARM64_FWD%"
echo ar = "%AR_FWD%"
echo.
echo [target.armv7-linux-androideabi]
echo linker = "%CC_ARM32_FWD%"
echo ar = "%AR_FWD%"
echo.
echo [target.x86_64-linux-android]
echo linker = "%CC_X64_FWD%"
echo ar = "%AR_FWD%"
echo.
echo [target.i686-linux-android]
echo linker = "%CC_X86_FWD%"
echo ar = "%AR_FWD%"
) > "%CARGO_DIR%\config.toml"

echo Config gerado: %CARGO_DIR%\config.toml

:: ── Compila cada ABI ──────────────────────────────────────────────────────────
set "FAILED=0"

call :build_abi aarch64-linux-android    arm64-v8a
call :build_abi armv7-linux-androideabi  armeabi-v7a
call :build_abi x86_64-linux-android     x86_64
call :build_abi i686-linux-android       x86

if "%FAILED%"=="0" (
    echo.
    echo ========================================
    echo Todos os ABIs compilados com sucesso!
    echo Os .a estao em: %SCRIPT_DIR%target\
    echo Agora execute: flutter run
    echo ========================================
) else (
    echo.
    echo AVISO: Alguns ABIs falharam. Verifique os erros acima.
    exit /b 1
)
exit /b 0

:: ── Subrotina de build ────────────────────────────────────────────────────────
:build_abi
set "TARGET=%~1"
set "ABI=%~2"
echo.
echo ── Compilando %TARGET% (%ABI%) ...
cargo build --release --target %TARGET% --manifest-path "%MANIFEST%"
if errorlevel 1 (
    echo FALHOU: %TARGET%
    set "FAILED=1"
) else (
    echo OK: %SCRIPT_DIR%target\%TARGET%\release\libquill_perf.a
)
exit /b 0
