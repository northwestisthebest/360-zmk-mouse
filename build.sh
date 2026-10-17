#!/usr/bin/env bash
# Build 360 Mouse firmware.
#
#   ./build.sh v1            release firmware for the hand-wired mice
#   ./build.sh v2            release firmware for the PCB mice
#   ./build.sh v1 debug      same plus USB logging (360_mouse_debug add-on)
#   ./build.sh all           v1 and v2 release
#
# Output: firmware/360_mouse_<variant>[-debug].uf2 in this repo.

set -euo pipefail

SDK=/home/nortem/zephyr-sdk-0.17.0
ZMK_APP=$HOME/Documents/zephyrproject/zmk/app
REPO=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = all ]; then
    "$0" v1 && "$0" v2
    exit
fi

VARIANT=${1:?usage: ./build.sh v1|v2|all [debug]}
MODE=${2:-release}

case "$VARIANT" in v1|v2) ;; *) echo "unknown variant: $VARIANT" >&2; exit 1 ;; esac

if [ "$MODE" = debug ]; then
    SHIELD="360_mouse_$VARIANT 360_mouse_debug"
    SNIPPET=(-S zmk-usb-logging)
    NAME="$VARIANT-debug"
else
    SHIELD="360_mouse_$VARIANT"
    SNIPPET=()
    NAME="$VARIANT"
fi

set +u
. /home/nortem/.zinstaller/env.sh
set -u

cd "$ZMK_APP"
west build -p -d "build/$NAME" -b nice_nano "${SNIPPET[@]}" -- \
    -DSHIELD="$SHIELD" -DZEPHYR_SDK_INSTALL_DIR="$SDK"

mkdir -p "$REPO/firmware"
cp "build/$NAME/zephyr/zmk.uf2" "$REPO/firmware/360_mouse_$NAME.uf2"
echo
echo "==> firmware/360_mouse_$NAME.uf2"
