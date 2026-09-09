#!/usr/bin/env bash
# win_loss_check.sh
#
# Manual sanity check that a Windows (MinGW-w64) cross-compiled build of
# rade_tx_wav/rade_rx_wav is numerically equivalent to the native Linux
# build: cross-compiles rade_c for Windows, runs both builds through the
# same TX/RX round trip (native Linux vs Windows binaries under Wine), and
# compares the resulting "loss" (radae/loss.py) and feature files.
#
# This is a toolchain-sanity spot check, not part of automated CI -- the
# toolchain isn't expected to change often enough to warrant a per-commit
# GitHub Actions job (see WINDOWS_BUILD_TODO.md for that discussion).
#
# Requires: mingw-w64 (x86_64-w64-mingw32-gcc/g++/windres), wine, cmake,
# and a sibling radae checkout (for wav/all.wav and loss.py).
#
# Usage: ./test/win_loss_check.sh [RADAE_DIR] [loss_tolerance]
#   RADAE_DIR       path to a radae checkout (default: ../radae, then ~/radae)
#   loss_tolerance  max allowed |linux_loss - win_loss| (default: 0.01)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADE_C_DIR="$(dirname "$SCRIPT_DIR")"
RADAE_DIR="${1:-}"
TOLERANCE="${2:-0.01}"

if [ -z "$RADAE_DIR" ]; then
    if [ -d "${RADE_C_DIR}/../radae" ]; then RADAE_DIR="${RADE_C_DIR}/../radae";
    elif [ -d ~/radae ]; then RADAE_DIR=~/radae;
    else echo "Can't find a radae checkout -- pass its path as the first argument"; exit 1; fi
fi
TEST_WAV="${RADAE_DIR}/wav/all.wav"

for tool in x86_64-w64-mingw32-gcc wine cmake python3; do
    which "$tool" >/dev/null || { echo "Can't find '$tool' -- please install it"; exit 1; }
done
[ -f "$TEST_WAV" ] || { echo "Can't find $TEST_WAV"; exit 1; }
[ -f "${RADAE_DIR}/loss.py" ] || { echo "Can't find ${RADAE_DIR}/loss.py"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "--- Building native Linux rade_tx_wav/rade_rx_wav ---"
mkdir -p "${RADE_C_DIR}/build"
(cd "${RADE_C_DIR}/build" && cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null && make -j"$(nproc)" rade_tx_wav rade_rx_wav >/dev/null 2>&1)

echo "--- Cross-compiling Windows rade_tx_wav.exe/rade_rx_wav.exe (MinGW-w64) ---"
mkdir -p "${RADE_C_DIR}/build-win"
(cd "${RADE_C_DIR}/build-win" && cmake -DCMAKE_TOOLCHAIN_FILE="${RADE_C_DIR}/cmake/toolchain-mingw64.cmake" -DCMAKE_BUILD_TYPE=Release .. >/dev/null && make -j"$(nproc)" rade_tx_wav rade_rx_wav >/dev/null 2>&1)

# libssp-0.dll (MinGW _FORTIFY_SOURCE runtime) isn't on Wine's search path by default
LIBSSP=$(x86_64-w64-mingw32-gcc -print-file-name=libssp-0.dll)
[ -f "$LIBSSP" ] && cp "$LIBSSP" "${RADE_C_DIR}/build-win/src/"

echo "--- Running native Linux round trip ---"
"${RADE_C_DIR}/build/src/rade_tx_wav"     --v2 -f "$WORK/linux_tx.f32" "$TEST_WAV" "$WORK/linux_tx.wav" 2>/dev/null
"${RADE_C_DIR}/build/src/rade_rx_wav"     --v2 -f "$WORK/linux_rx.f32" "$WORK/linux_tx.wav" "$WORK/linux_decoded.wav" 2>/dev/null

echo "--- Running Windows round trip (Wine) ---"
(cd "${RADE_C_DIR}/build-win/src" && wine ./rade_tx_wav.exe --v2 -f "$WORK/win_tx.f32" "$TEST_WAV" "$WORK/win_tx.wav" 2>/dev/null)
(cd "${RADE_C_DIR}/build-win/src" && wine ./rade_rx_wav.exe --v2 -f "$WORK/win_rx.f32" "$WORK/win_tx.wav" "$WORK/win_decoded.wav" 2>/dev/null)

echo "--- Comparing ---"
LINUX_LOSS=$(cd "$RADAE_DIR" && python3 loss.py "$WORK/linux_tx.f32" "$WORK/linux_rx.f32" --clip_start 25 | grep "loss:" | awk '{print $2}')
WIN_LOSS=$(cd "$RADAE_DIR" && python3 loss.py "$WORK/win_tx.f32" "$WORK/win_rx.f32" --clip_start 25 | grep "loss:" | awk '{print $2}')

echo "Linux   loss: $LINUX_LOSS"
echo "Windows loss: $WIN_LOSS"

python3 - "$LINUX_LOSS" "$WIN_LOSS" "$TOLERANCE" "$WORK/linux_tx.f32" "$WORK/win_tx.f32" "$WORK/linux_rx.f32" "$WORK/win_rx.f32" <<'EOF'
import sys
import numpy as np

linux_loss, win_loss, tol = (float(x) for x in sys.argv[1:4])
linux_tx_f, win_tx_f, linux_rx_f, win_rx_f = sys.argv[4:8]

delta = abs(linux_loss - win_loss)
print(f"|delta|: {delta:.4f}  (tolerance: {tol})")

for label, a_f, b_f in [("TX features", linux_tx_f, win_tx_f), ("RX features", linux_rx_f, win_rx_f)]:
    a = np.fromfile(a_f, dtype=np.float32)
    b = np.fromfile(b_f, dtype=np.float32)
    n = min(len(a), len(b))
    diff = np.abs(a[:n] - b[:n])
    print(f"{label}: max abs diff {diff.max():.6f}  RMS diff {np.sqrt((diff**2).mean()):.6f}")

if delta > tol:
    print("FAIL: loss delta exceeds tolerance")
    sys.exit(1)
print("PASS")
EOF
