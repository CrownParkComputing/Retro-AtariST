#!/usr/bin/env bash
# Build the core for iOS as a .framework.
#
# A framework rather than a loose dylib, and that is not a style choice: iOS
# validates every nested Mach-O under Frameworks/ as a code bundle and rejects
# the install outright (ApplicationVerificationFailed) if one is a bare dylib.
# Retro-Dosbox hit exactly this and carries a tools/fix-ipa-native-assets.sh
# to repair it after the fact; producing the right shape here avoids that.
# The same two accommodations Android needs, for the same reasons:
#   SDL2_DIR + FIND_ROOT_PATH_MODE -> Hatari's CMake FATAL_ERRORs without an
#     SDL package even though we link none of it.
#   ENABLE_DSP_EMU=0 -> falcon/dsp_cpu.c is the only source needing a real SDL
#     header. Falcon DSP; no ST or STE title uses it.
#
# NOTE: this script has never been run -- there is no macOS machine in the loop
# yet. Expect to fix things on the first real attempt, starting with
# bridge/audio_sink_ios.m, which has never been compiled.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(dirname "$here")"

sdk="${1:-iphoneos}"          # or iphonesimulator
arch="${2:-arm64}"
build="$here/build-$sdk-$arch"

root="$(cd "$core/../.." && pwd)"
cmake -S "$root/vendor/hatari" -B "$build" -G Xcode \
	-DCMAKE_PROJECT_INCLUDE="$core/embed.cmake" \
	-DSDL2_DIR="$core/cmake-stubs" \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
	-DENABLE_SDL3=0 \
	-DENABLE_DSP_EMU=0 \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$sdk" \
	-DCMAKE_OSX_ARCHITECTURES="$arch" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_FRAMEWORK=ON \
	"${@:3}"
cmake --build "$build" --target atarist_core --config Release

echo "built under $build -- copy libatarist_core.framework into the Runner target."
