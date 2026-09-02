#!/usr/bin/env bash
# Build libatarist_core.so for the host.
#
# Used by native bridge/frontend smoke tests and host-side profiling.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(dirname "$here")"
root="$(cd "$core/../.." && pwd)"

if [ ! -f "$root/vendor/hatari/src/main.c" ]; then
	echo "vendor/hatari is empty. Run:" >&2
	echo "    git submodule update --init --recursive" >&2
	exit 1
fi

# Hatari is the top-level project; we are injected into it. See embed.cmake.
build="$here/build"
cmake -S "$root/vendor/hatari" -B "$build" \
	-DCMAKE_PROJECT_INCLUDE="$core/embed.cmake" \
	-DCMAKE_BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}" \
	"$@"
# --target, so the `hatari` executable and the SDL front end are never built.
cmake --build "$build" --target atarist_core --parallel "$(nproc)"

echo
echo "built: $build/libatarist_core.so"
# Worth printing: an accidentally-exported Hatari symbol is invisible until it
# collides with something in the host process months later.
echo -n "exported symbols: "
nm -D --defined-only "$build/libatarist_core.so" | grep -c ' T ' || true
