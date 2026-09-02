#!/usr/bin/env bash
# Compatibility entry point. The app-level script owns the native iOS build.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
exec "$repo_root/ios/build.sh" "$@"
