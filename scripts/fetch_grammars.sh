#!/usr/bin/env bash
# scripts/fetch_grammars.sh
#
# Clones (or updates) tree-sitter core + all grammar repos into
# android/src/main/cpp/.
#
# Run once before building:
#   cd <project_root>
#   bash scripts/fetch_grammars.sh

set -euo pipefail

# ── Disable Windows credential manager / interactive prompts ─────────────────
# These repos are all PUBLIC — no auth needed. Suppress any credential popup.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=echo
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0="credential.helper"
export GIT_CONFIG_VALUE_0=""
export GIT_CONFIG_KEY_1="core.askPass"
export GIT_CONFIG_VALUE_1=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_DIR="$SCRIPT_DIR/../android/src/main/cpp"

echo "QuillCode — fetching tree-sitter grammars"
echo "Target: $CPP_DIR"
echo ""

# ── Helper ────────────────────────────────────────────────────────────────────
clone_or_update() {
  local url="$1"
  local dir="$2"
  local branch="${3:-master}"

  # Git flags: disable credential helpers, anonymous access only
  local GIT_FLAGS="-c credential.helper= -c core.askPass="

  if [ -d "$dir/.git" ]; then
    echo "  ↺  updating  $(basename "$dir")"
    # Fetch all tags so we can switch to a different version if needed
    git $GIT_FLAGS -C "$dir" fetch --quiet --tags origin 2>/dev/null || true
    git $GIT_FLAGS -C "$dir" checkout --quiet "$branch" 2>/dev/null ||     git $GIT_FLAGS -C "$dir" checkout --quiet "main"    2>/dev/null ||     git $GIT_FLAGS -C "$dir" pull --quiet 2>/dev/null || true
  elif [ -d "$dir" ]; then
    # Exists but is not a git repo (e.g. manually created placeholder) — remove it
    echo "  ✗  removing stale dir  $(basename "$dir")"
    rm -rf "$dir"
    echo "  ↓  cloning   $(basename "$dir")"
    git $GIT_FLAGS clone --quiet --depth=1 --branch "$branch" "$url" "$dir" 2>/dev/null || \
    git $GIT_FLAGS clone --quiet --depth=1 "$url" "$dir"
  else
    echo "  ↓  cloning   $(basename "$dir")"
    git $GIT_FLAGS clone --quiet --depth=1 --branch "$branch" "$url" "$dir" 2>/dev/null || \
    git $GIT_FLAGS clone --quiet --depth=1 "$url" "$dir"
  fi
}

mkdir -p "$CPP_DIR"

# ── Tree-sitter runtime ───────────────────────────────────────────────────────
clone_or_update \
  "https://github.com/tree-sitter/tree-sitter.git" \
  "$CPP_DIR/tree-sitter" \
  "v0.22.6"

# ── Grammars ──────────────────────────────────────────────────────────────────
GRAM="$CPP_DIR/grammars"
mkdir -p "$GRAM"

clone_or_update "https://github.com/UserNobody14/tree-sitter-dart.git"        "$GRAM/tree-sitter-dart"
clone_or_update "https://github.com/tree-sitter/tree-sitter-javascript.git"  "$GRAM/tree-sitter-javascript"
clone_or_update "https://github.com/tree-sitter/tree-sitter-typescript.git"  "$GRAM/tree-sitter-typescript"
clone_or_update "https://github.com/tree-sitter/tree-sitter-python.git"      "$GRAM/tree-sitter-python"
clone_or_update "https://github.com/fwcd/tree-sitter-kotlin.git"             "$GRAM/tree-sitter-kotlin"
clone_or_update "https://github.com/tree-sitter/tree-sitter-rust.git"        "$GRAM/tree-sitter-rust"
clone_or_update "https://github.com/tree-sitter/tree-sitter-cpp.git"         "$GRAM/tree-sitter-cpp"
clone_or_update "https://github.com/tree-sitter/tree-sitter-c.git"           "$GRAM/tree-sitter-c"
clone_or_update "https://github.com/tree-sitter/tree-sitter-html.git"        "$GRAM/tree-sitter-html"
clone_or_update "https://github.com/tree-sitter/tree-sitter-css.git"         "$GRAM/tree-sitter-css"
clone_or_update "https://github.com/tree-sitter/tree-sitter-json.git"        "$GRAM/tree-sitter-json"
clone_or_update "https://github.com/ikatyang/tree-sitter-yaml.git"           "$GRAM/tree-sitter-yaml"
clone_or_update "https://github.com/tree-sitter/tree-sitter-bash.git"        "$GRAM/tree-sitter-bash"
clone_or_update "https://github.com/ObserverOfTime/tree-sitter-xml.git"      "$GRAM/tree-sitter-xml"

echo ""
echo "✓ Done. All grammars ready in:"
echo "  $CPP_DIR"
echo ""
echo "Next: flutter build apk  (Gradle will compile libquill_ts.so automatically)"
