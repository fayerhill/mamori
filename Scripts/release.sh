#!/bin/zsh
set -euo pipefail

# Package an existing build. This does not rebuild, launch, install, or notarize.
project_dir="${0:A:h:h}"
cd "$project_dir"
make_dmg=false
case "${1:-}" in
    "") ;;
    --dmg) make_dmg=true ;;
    *) print -u2 'Usage: ./Scripts/release.sh [--dmg]'; exit 2 ;;
esac
if (( $# > 1 )); then
    print -u2 'Usage: ./Scripts/release.sh [--dmg]'
    exit 2
fi
for archive in 'build/Mamori.zip' 'build/Mamori Preview.zip'; do
    if [[ ! -f "$archive" ]]; then
        print -u2 "Missing $archive. Build the final source with ./Scripts/build.sh first."
        exit 1
    fi
done

release_stage="$(mktemp -d /private/tmp/mamori-release.XXXXXX)"
trap 'rm -rf "$release_stage"' EXIT
normal_dir="$release_stage/Mamori"
preview_dir="$release_stage/Mamori Preview"
mkdir -p "$normal_dir" "$preview_dir" "$release_stage/assets"
# Use clean archives, not app copies that a File Provider may have decorated.
ditto -x -k 'build/Mamori.zip' "$normal_dir"
ditto -x -k 'build/Mamori Preview.zip' "$preview_dir"
normal_app="$normal_dir/Mamori.app"
preview_app="$preview_dir/Mamori Preview.app"
for app_bundle in "$normal_app" "$preview_app"; do
    codesign --verify --deep --strict "$app_bundle"
done
codesign --verify --strict "$normal_app/Contents/MacOS/MamoriGuard"

normal_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$normal_app/Contents/Info.plist")"
preview_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$preview_app/Contents/Info.plist")"
if [[ "$normal_id" != com.mamori.app || "$preview_id" != com.mamori.preview ]]; then
    print -u2 'The input archives do not contain the expected Mamori apps.'
    exit 1
fi
normal_arch="$(lipo -archs "$normal_app/Contents/MacOS/Mamori")"
if [[ "$(lipo -archs "$preview_app/Contents/MacOS/Mamori")" != "$normal_arch" ||
      "$(lipo -archs "$normal_app/Contents/MacOS/MamoriGuard")" != "$normal_arch" ]]; then
    print -u2 'The app, preview, and helper architectures must match.'
    exit 1
fi
case "$normal_arch" in
    arm64) asset_arch=arm64 ;;
    x86_64) asset_arch=x86_64 ;;
    'arm64 x86_64'|'x86_64 arm64') asset_arch=universal ;;
    *) print -u2 "Unsupported release architecture: $normal_arch"; exit 1 ;;
esac
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$normal_app/Contents/Info.plist")"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$preview_app/Contents/Info.plist")" != "$version" ]]; then
    print -u2 'The app and preview versions must match.'
    exit 1
fi

cat > "$release_stage/Quick Start.txt" <<'EOF'
MAMORI — DEVELOPMENT DOWNLOAD

Install without Terminal
1. Open the ZIP, or double-click the disk image.
2. Drag the app you want into Applications.
3. Open it from Applications. Click the shield in the menu bar to show Mamori.
   You do not need Xcode or Homebrew to use these app downloads.

Choose an app
- Mamori.app: real keep-awake controls and read-only GlobalProtect observation.
  In this ad-hoc development build, privileged network protection is unavailable.
  Automatic app quitting requires an armed guard and is unavailable here too.
  The presence of a VPN connection does not mean Mamori is protecting traffic.
- Mamori Preview.app: an interactive simulation. VPN, firewall, keep-awake and
  application-quit effects are simulated. The installed-app picker is read-only.
  Preview and normal mode have different app names; Preview is clearly labeled.

First launch
These are development downloads, not notarized distribution releases. macOS may
block opening them. If you trust this project and download, attempt to open the
app, then review System Settings > Privacy & Security > Open Anyway when offered.
Managed Macs may not offer an override. Do not disable Gatekeeper globally.
Apple's instructions: https://support.apple.com/102445

Use and quit
Keep-awake starts off. It prevents idle system sleep while enabled, allowing the
display to sleep or lock; it does not defeat lid closure or explicit sleep.
Use Restore & Quit from the app before removing it. If a separately signed guard
was installed later, restore and remove that service before deleting the app.
Preview does not install a background service. Network leak testing and signed
helper installation have not been performed for this development download.

Requirements
macOS 14 or later. The filename identifies the supported processor architecture:
arm64 = Apple silicon; x86_64 = Intel; universal = both.
EOF

# Keep the guide truthful if a maintainer supplies a Developer ID build later.
signature_info="$(codesign -dvv "$normal_app" 2>&1)"
if [[ "$signature_info" != *'Signature=adhoc'* ]]; then
    print -u2 'This packager currently targets ad-hoc development downloads. Update the distribution guide before packaging a Developer ID release.'
    exit 1
fi
for package_dir in "$normal_dir" "$preview_dir"; do
    install -m 644 "$release_stage/Quick Start.txt" "$package_dir/Quick Start.txt"
done
assets_dir="$release_stage/assets"
normal_name="Mamori-macOS-$asset_arch.zip"
preview_name="Mamori-Preview-macOS-$asset_arch.zip"
ditto -c -k --norsrc --noextattr --keepParent "$normal_dir" "$assets_dir/$normal_name"
ditto -c -k --norsrc --noextattr --keepParent "$preview_dir" "$assets_dir/$preview_name"
asset_names=("$normal_name" "$preview_name")

if $make_dmg; then
    if [[ ! -x /usr/bin/hdiutil ]]; then
        print -u2 'hdiutil is required for --dmg. Omit --dmg to produce ZIP downloads.'
        exit 1
    fi
    disk_dir="$release_stage/disk"
    mkdir -p "$disk_dir"
    ditto --norsrc --noextattr "$normal_app" "$disk_dir/Mamori.app"
    ditto --norsrc --noextattr "$preview_app" "$disk_dir/Mamori Preview.app"
    install -m 644 "$release_stage/Quick Start.txt" "$disk_dir/Quick Start.txt"
    ln -s /Applications "$disk_dir/Applications"
    disk_name="Mamori-macOS-$asset_arch.dmg"
    hdiutil create -quiet -srcfolder "$disk_dir" -volname 'Mamori' -format UDZO "$assets_dir/$disk_name"
    asset_names+=("$disk_name")
fi
(
    cd "$assets_dir"
    shasum -a 256 "${asset_names[@]}" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
output_dir="$project_dir/build/release"
mkdir -p "$output_dir"
for asset in "${asset_names[@]}" SHA256SUMS; do
    install -m 644 "$assets_dir/$asset" "$output_dir/$asset"
done
print "Prepared Mamori $version development downloads in $output_dir"
print 'Upload only the assets listed in SHA256SUMS and SHA256SUMS itself.'
print 'Packaging did not launch an app, install a helper, change the network, or notarize anything.'
