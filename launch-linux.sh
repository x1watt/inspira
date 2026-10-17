#!/usr/bin/env bash
# Launches the already built Linux release of Inspira, without compiling.
# Build it first (or again after changes) with:
#   ~/bin/android-build-locked flutter build linux
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$dir/build/linux/x64/release/bundle/inspira"

if [[ ! -x "$bin" ]]; then
  echo "No Linux build found at $bin" >&2
  echo "Build it once with: ~/bin/android-build-locked flutter build linux" >&2
  exit 1
fi

# The Dart code is in lib/libapp.so; the launcher binary rarely changes.
app="$dir/build/linux/x64/release/bundle/lib/libapp.so"
if [[ -n "$(find "$dir/lib" "$dir/assets" -newer "$app" -print -quit)" ]]; then
  echo "Note: sources changed since the last build; rebuild to see the changes." >&2
fi

exec "$bin" "$@"
