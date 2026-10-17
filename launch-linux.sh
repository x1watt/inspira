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

# A menu entry with the icon; its name matches the application id
# (linux/CMakeLists.txt), so the dock shows the icon for the window too.
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
if [[ -d "$apps" ]]; then
  cat > "$apps/com.x1watt.inspira.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Inspira
Comment=Quotes, stories and history, offline
Exec=$dir/launch-linux.sh
Icon=$dir/build/linux/x64/release/bundle/data/app_icon.png
StartupWMClass=com.x1watt.inspira
Categories=Education;
EOF
fi

exec "$bin" "$@"
