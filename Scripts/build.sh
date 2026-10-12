#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
configuration="${CONFIGURATION:-debug}"
bundle_stage="$(mktemp -d /private/tmp/mamori-bundles.XXXXXX)"
trap 'rm -rf "$bundle_stage"' EXIT
app_dir="$bundle_stage/Mamori.app"
signing_identity="${SIGNING_IDENTITY:--}"

export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/ModuleCache"
swift build -c "$configuration" --cache-path "$project_dir/.build/cache" --config-path "$project_dir/.build/config" --security-path "$project_dir/.build/security" --disable-sandbox
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Library/LaunchDaemons"
install -m 755 ".build/$configuration/Mamori" "$app_dir/Contents/MacOS/Mamori"
install -m 755 ".build/$configuration/MamoriGuard" "$app_dir/Contents/MacOS/MamoriGuard"
install -m 644 Resources/Info.plist "$app_dir/Contents/Info.plist"
install -m 644 Resources/com.mamori.guard.plist "$app_dir/Contents/Library/LaunchDaemons/com.mamori.guard.plist"
if [[ -f Resources/Mamori.icns ]]; then
    install -m 644 Resources/Mamori.icns "$app_dir/Contents/Resources/Mamori.icns"
fi
if [[ -f Resources/MamoriIcon.png ]]; then
    install -m 644 Resources/MamoriIcon.png "$app_dir/Contents/Resources/MamoriIcon.png"
fi
# Generated bundles in a File Provider folder can acquire Finder metadata.
# Strip metadata only from this disposable build product before signing it.
xattr -cr "$app_dir"

codesign --force --options runtime --timestamp=none --identifier com.mamori.guard --sign "$signing_identity" "$app_dir/Contents/MacOS/MamoriGuard"
codesign --force --options runtime --timestamp=none --identifier com.mamori.app --sign "$signing_identity" "$app_dir"
codesign --verify --strict "$app_dir"

# A separate preview bundle always selects fake services, even when opened by Finder.
preview_dir="$bundle_stage/Mamori Preview.app"
mkdir -p "$preview_dir/Contents/MacOS" "$preview_dir/Contents/Resources"
install -m 755 ".build/$configuration/Mamori" "$preview_dir/Contents/MacOS/Mamori"
install -m 644 Resources/Info.plist "$preview_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.mamori.preview' "$preview_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Mamori Preview' "$preview_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Mamori Preview' "$preview_dir/Contents/Info.plist"
for asset in Mamori.icns MamoriIcon.png; do
    if [[ -f "Resources/$asset" ]]; then
        install -m 644 "Resources/$asset" "$preview_dir/Contents/Resources/$asset"
    fi
done
xattr -cr "$preview_dir"
codesign --force --options runtime --timestamp=none --identifier com.mamori.preview --sign - "$preview_dir"
codesign --verify --strict "$preview_dir"
mkdir -p "$project_dir/build"
ditto --norsrc --noextattr "$app_dir" "$project_dir/build/Mamori.app"
ditto --norsrc --noextattr "$preview_dir" "$project_dir/build/Mamori Preview.app"
# Archive from the verified staging directory before File Provider can add metadata.
ditto -c -k --norsrc --noextattr --keepParent "$app_dir" "$project_dir/build/Mamori.zip"
ditto -c -k --norsrc --noextattr --keepParent "$preview_dir" "$project_dir/build/Mamori Preview.zip"
print "Built $project_dir/build/Mamori.app"
print "Built $project_dir/build/Mamori Preview.app"
if [[ "$signing_identity" == "-" ]]; then
    print "Ad-hoc local build: network protection requires a Developer ID signed build."
fi
