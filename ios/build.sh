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
cpu_source="$repo_root/vendor/hatari/src/cpu"
cpu_build="$build_dir/src/cpu"

# Hatari normally creates these sources from Xcode build phases. A Darwin host
# targeting iOS is not consistently treated as a cross-build by CMake/Xcode,
# so the small generators can accidentally become simulator executables and
# fail when the Mac tries to run them. Generate the architecture-independent C
# sources up front with the macOS compiler instead.
mkdir -p "$cpu_build"
"$script_dir/host-tools/cc" -I"$cpu_source" \
	"$cpu_source/build68k.c" "$cpu_source/writelog.c" \
	-o "$cpu_build/build68k"
"$cpu_build/build68k" < "$cpu_source/table68k" > "$cpu_build/cpudefs.c"
"$script_dir/host-tools/cc" -I"$cpu_source" \
	"$cpu_build/cpudefs.c" "$cpu_source/gencpu.c" "$cpu_source/readcpu.c" \
	-o "$cpu_build/gencpu"
(
	cd "$cpu_build"
	./gencpu
)

cmake -S "$repo_root/vendor/hatari" -B "$build_dir" -G Xcode \
	-DCMAKE_PROJECT_INCLUDE="$repo_root/native/atarist_core/embed.cmake" \
	-DSDL2_DIR="$repo_root/native/atarist_core/cmake-stubs" \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
	-DENABLE_SDL3=0 \
	-DENABLE_DSP_EMU=0 \
	-DENABLE_OSX_BUNDLE=0 \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$sdk" \
	-DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_XCODE_GENERATE_SCHEME=ON \
	"${@:2}"
cmake --build "$build_dir" --config Release --target RetroAtariST
