#!/bin/bash
#
# Produces self-contained `surge` + `aria2c` binaries so the app can ship them
# without requiring the user to `brew install` anything.
#
# For aria2c (which links several Homebrew dylibs) we copy the full transitive
# dependency closure that lives under /opt/homebrew, rewrite every load command
# to @loader_path/<leaf> so the folder is relocatable, and ad-hoc re-sign each
# Mach-O (install_name_tool invalidates code signatures on Apple Silicon).
#
# Usage: tools/bundle_macos_binaries.sh [output_dir]
#   default output_dir: native/macos/bin (relative to repo root)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/native/macos/bin}"

SURGE_BIN="${SURGE_BIN:-/opt/homebrew/bin/surge}"
ARIA_BIN="${ARIA_BIN:-/opt/homebrew/bin/aria2c}"

echo "==> Output: $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"

# Copy the primary executables, dereferencing symlinks (-L).
cp -L "$SURGE_BIN" "$OUT/surge"
cp -L "$ARIA_BIN" "$OUT/aria2c"
chmod u+w "$OUT/surge" "$OUT/aria2c"

QUEUE="$OUT/.queue"
: > "$QUEUE"

# Copy any /opt/homebrew dylib deps of $1 into $OUT (once each), enqueueing new
# ones for their own dependency scan.
collect() {
  local f="$1"
  otool -L "$f" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      /opt/homebrew/*)
        local leaf
        leaf="$(basename "$dep")"
        if [ ! -f "$OUT/$leaf" ]; then
          cp -L "$dep" "$OUT/$leaf"
          chmod u+w "$OUT/$leaf"
          echo "$dep" >> "$QUEUE"
          echo "    + $leaf"
        fi
        ;;
    esac
  done
}

echo "==> Resolving dependency closure"
collect "$OUT/aria2c"
collect "$OUT/surge"

# Breadth-first over the growing queue file.
processed=0
while :; do
  line="$(sed -n "$((processed + 1))p" "$QUEUE")"
  [ -z "$line" ] && break
  collect "$OUT/$(basename "$line")"
  processed=$((processed + 1))
done
rm -f "$QUEUE"

# Rewrite ids + load commands to @loader_path so the bundle is relocatable.
echo "==> Relinking to @loader_path"
for f in "$OUT"/*; do
  base="$(basename "$f")"
  install_name_tool -id "@loader_path/$base" "$f" 2>/dev/null || true
  otool -L "$f" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      /opt/homebrew/*)
        install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$f"
        ;;
    esac
  done
done

# install_name_tool invalidates signatures; ad-hoc re-sign every Mach-O.
echo "==> Ad-hoc re-signing"
for f in "$OUT"/*; do
  codesign --remove-signature "$f" 2>/dev/null || true
  codesign --force --sign - "$f"
done

echo "==> Done:"
ls -la "$OUT"
