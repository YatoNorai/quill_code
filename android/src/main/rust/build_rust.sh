#!/usr/bin/env bash
# build_rust.sh — compila libquill_perf.a para todos os ABIs Android
# Pré-requisitos:
#   1. Rust instalado: https://rustup.rs
#   2. Android NDK r26+ instalado via Android Studio
#
# Uso:
#   ./android/src/main/rust/build_rust.sh
#   ./android/src/main/rust/build_rust.sh /path/to/ndk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/Cargo.toml"

# ── Detecta NDK ──────────────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
    NDK="$1"
elif [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    NDK="$ANDROID_NDK_HOME"
elif [[ -n "${ANDROID_NDK:-}" ]]; then
    NDK="$ANDROID_NDK"
else
    # Tenta localização padrão Linux/macOS
    if [[ -d "$HOME/Android/Sdk/ndk" ]]; then
        NDK="$HOME/Android/Sdk/ndk/$(ls "$HOME/Android/Sdk/ndk" | tail -1)"
    elif [[ -d "$HOME/Library/Android/sdk/ndk" ]]; then
        NDK="$HOME/Library/Android/sdk/ndk/$(ls "$HOME/Library/Android/sdk/ndk" | tail -1)"
    else
        echo "ERRO: NDK não encontrado. Defina ANDROID_NDK_HOME ou passe como argumento."
        exit 1
    fi
fi

[[ -d "$NDK" ]] || { echo "ERRO: NDK não encontrado em: $NDK"; exit 1; }
echo "NDK: $NDK"

# Detecta OS do host para o toolchain correto
case "$(uname -s)" in
    Linux*)  HOST_TAG="linux-x86_64";;
    Darwin*) HOST_TAG="darwin-x86_64";;
    *)       echo "ERRO: OS não suportado: $(uname -s)"; exit 1;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
[[ -d "$TOOLCHAIN" ]] || { echo "ERRO: Toolchain não encontrado: $TOOLCHAIN"; exit 1; }

# ── Verifica cargo ────────────────────────────────────────────────────────────
command -v cargo &>/dev/null || {
    echo "ERRO: cargo não encontrado. Instale: https://rustup.rs"
    exit 1
}

# ── Instala targets ───────────────────────────────────────────────────────────
echo "Instalando targets Rust..."
rustup target add \
    aarch64-linux-android \
    armv7-linux-androideabi \
    x86_64-linux-android \
    i686-linux-android

# ── Cria .cargo/config.toml ───────────────────────────────────────────────────
API=21
mkdir -p "$SCRIPT_DIR/.cargo"
cat > "$SCRIPT_DIR/.cargo/config.toml" << EOF
[target.aarch64-linux-android]
linker = "$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"
ar     = "$TOOLCHAIN/bin/llvm-ar"

[target.armv7-linux-androideabi]
linker = "$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang"
ar     = "$TOOLCHAIN/bin/llvm-ar"

[target.x86_64-linux-android]
linker = "$TOOLCHAIN/bin/x86_64-linux-android${API}-clang"
ar     = "$TOOLCHAIN/bin/llvm-ar"

[target.i686-linux-android]
linker = "$TOOLCHAIN/bin/i686-linux-android${API}-clang"
ar     = "$TOOLCHAIN/bin/llvm-ar"
EOF
echo "Config gerado: $SCRIPT_DIR/.cargo/config.toml"

# ── Compila cada ABI ──────────────────────────────────────────────────────────
FAILED=0
build_abi() {
    local target="$1"
    local abi="$2"
    echo ""
    echo "── Compilando $target ($abi) ..."
    if cargo build --release --target "$target" --manifest-path "$MANIFEST"; then
        echo "OK: $SCRIPT_DIR/target/$target/release/libquill_perf.a"
    else
        echo "FALHOU: $target"
        FAILED=1
    fi
}

build_abi aarch64-linux-android    arm64-v8a
build_abi armv7-linux-androideabi  armeabi-v7a
build_abi x86_64-linux-android     x86_64
build_abi i686-linux-android       x86

echo ""
if [[ "$FAILED" == "0" ]]; then
    echo "========================================"
    echo "Todos os ABIs compilados com sucesso!"
    echo "Agora execute: flutter run"
    echo "========================================"
else
    echo "AVISO: Alguns ABIs falharam. Verifique os erros acima."
    exit 1
fi
