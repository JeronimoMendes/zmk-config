#!/usr/bin/env bash
# Local Docker build for ZMK corne firmware.
# Usage:
#   ./build.sh              # build both halves
#   ./build.sh left         # build only left
#   ./build.sh right        # build only right
#   ./build.sh clean        # wipe build/ and west workspace
#
# Outputs UF2 files into ./firmware/
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$CONFIG_DIR/.zmk-workspace"
IMAGE="zmkfirmware/zmk-build-arm:stable"
BOARD="nice_nano_v2"

mkdir -p "$WORKSPACE" "$CONFIG_DIR/firmware"

run_in_container() {
    docker run --rm ${DOCKER_TTY:--i} \
        -e ZEPHYR_BASE=/workspace/zephyr \
        -v "$WORKSPACE":/workspace \
        -v "$CONFIG_DIR":/workspace/config-repo \
        -v "$CONFIG_DIR/config":/workspace/config \
        -v "$CONFIG_DIR/firmware":/workspace/firmware \
        -w /workspace \
        "$IMAGE" \
        bash -c "$1"
}

init_workspace() {
    if [ ! -d "$WORKSPACE/.west" ]; then
        echo ">>> Initializing west workspace (first run, downloads ZMK + Zephyr)..."
        run_in_container "west init -l config && west update && west zephyr-export"
    elif [ ! -d "$WORKSPACE/zmk-nice-oled" ]; then
        # west.yml changed (new module/revision) — refresh the workspace.
        echo ">>> Manifest changed, running west update..."
        run_in_container "west update && west zephyr-export"
    fi
}

# build_shield <name> <shield-spec> [snippet] [extra-cmake-args]
#   <name>             used for the build dir and output uf2 filename
#   <shield-spec>      value passed to -DSHIELD (may contain multiple shields)
#   [snippet]          optional west snippet, e.g. studio-rpc-usb-uart
#   [extra-cmake-args] optional cmake args after --, e.g. -DCONFIG_ZMK_STUDIO=y
build_shield() {
    local name="$1"
    local shields="$2"
    local snippet="${3:-}"
    local extra_args="${4:-}"
    local snippet_flag=""
    [ -n "$snippet" ] && snippet_flag="-S $snippet"
    echo ">>> Building $name ($shields)..."
    run_in_container "cd /workspace && west zephyr-export && rm -rf build/$name && west build -d build/$name -s zmk/app -b $BOARD $snippet_flag -- -DSHIELD=\"$shields\" -DZMK_CONFIG=/workspace/config $extra_args && cp build/$name/zephyr/zmk.uf2 firmware/${name}.uf2"
    echo ">>> firmware/${name}.uf2"
}

case "${1:-both}" in
    clean)
        rm -rf "$WORKSPACE" "$CONFIG_DIR/firmware"
        echo "Cleaned."
        ;;
    left)
        init_workspace
        build_shield corne_left "corne_left nice_oled" studio-rpc-usb-uart -DCONFIG_ZMK_STUDIO=y
        ;;
    right)
        init_workspace
        build_shield corne_right "corne_right nice_oled"
        ;;
    reset)
        init_workspace
        build_shield settings_reset "settings_reset"
        ;;
    both|"")
        init_workspace
        build_shield corne_left "corne_left nice_oled" studio-rpc-usb-uart -DCONFIG_ZMK_STUDIO=y
        build_shield corne_right "corne_right nice_oled"
        ;;
    *)
        echo "Usage: $0 [left|right|both|clean]" >&2
        exit 1
        ;;
esac
