#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app=build/PatsHelloworld-Soundboard.app
architectures=("$(uname -m)")
case "${1:-}" in
  "") ;;
  --universal) architectures=(arm64 x86_64) ;;
  *) echo "Usage: bash build.sh [--universal]" >&2; exit 2 ;;
esac

mkdir -p build/module-cache
package=$(mktemp -d build/package.XXXXXX)
trap 'rm -rf "$package"' EXIT
bundle="$package/PatsHelloworld-Soundboard.app"
resources="$bundle/Contents/Resources"
iconset="$package/AppIcon.iconset"
mkdir -p "$bundle/Contents/MacOS" "$resources" "$iconset"
cp index.html "$resources/"
python3 generate_assets.py "$resources/sounds"

for size in 16 32 128 256 512; do
  retina=$((size * 2))
  sips -z "$size" "$size" AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z "$retina" "$retina" AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"
sips -z 180 180 AppIcon.png --out "$resources/touch.png" >/dev/null
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Soundboard</string>
<key>CFBundleIdentifier</key><string>com.patshelloworld.localsoundboard</string>
<key>CFBundleName</key><string>PatsHelloworld Soundboard</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.5.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSLocalNetworkUsageDescription</key><string>Connect to your iPhone over Wi-Fi to play sound effects.</string>
</dict></plist>
PLIST
executables=()
for architecture in "${architectures[@]}"; do
  executable="$package/Soundboard-$architecture"
  swiftc -O -target "$architecture-apple-macosx13.0" -module-cache-path "build/module-cache/$architecture" \
    Soundboard.swift OBS.swift -o "$executable"
  executables+=("$executable")
done
binary="$bundle/Contents/MacOS/Soundboard"
if [[ ${#executables[@]} -eq 1 ]]; then
  mv "${executables[0]}" "$binary"
else
  lipo -create "${executables[@]}" -output "$binary"
fi
codesign --force --sign - "$bundle"
rm -rf "$app"
mv "$bundle" "$app"
