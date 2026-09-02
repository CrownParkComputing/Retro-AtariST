#!/usr/bin/env bash
set -euo pipefail

sdk="${1:-iphoneos}"
case "$sdk" in
	iphoneos|iphonesimulator) ;;
	*)
		echo "usage: $0 [iphoneos|iphonesimulator] [-DDEVELOPMENT_TEAM=TEAM_ID]" >&2
		exit 2
		;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(dirname "$script_dir")"
build_dir="$script_dir/build/$sdk"

cmake -S "$repo_root/vendor/hatari" -B "$build_dir" -G Xcode \
	-DCMAKE_PROJECT_INCLUDE="$repo_root/native/atarist_core/embed.cmake" \
	-DSDL2_DIR="$repo_root/native/atarist_core/cmake-stubs" \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
	-DENABLE_SDL3=0 \
	-DENABLE_DSP_EMU=0 \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$sdk" \
	-DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
	-DCMAKE_BUILD_TYPE=Release \
	"${@:2}"
cmake --build "$build_dir" --config Release --target RetroAtariST
