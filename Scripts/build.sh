#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/Scripts/lib/bundles.zsh"
configuration="${CONFIGURATION:-debug}"
output_dir="${BUILD_OUTPUT_DIR:-$project_dir/build}"
output_dir="${output_dir:A}"
[[ "$output_dir" != / ]] || { mamori_fail "BUILD_OUTPUT_DIR must not be the filesystem root."; exit 2; }
signing_mode="${SIGNING_MODE:-auto}"
signing_identity="${SIGNING_IDENTITY:-}"
case "$configuration" in debug|release) ;; *) mamori_fail 'CONFIGURATION must be debug or release.'; exit 2 ;; esac
case "$signing_mode" in auto|dev|developerID|adhoc) ;; *) mamori_fail 'SIGNING_MODE must be auto, dev, developerID, or adhoc.'; exit 2 ;; esac

if [[ "$signing_mode" == adhoc ]]; then
    [[ -z "$signing_identity" || "$signing_identity" == - ]] || { mamori_fail 'Ad-hoc mode does not accept a certificate identity.'; exit 2; }
    signing_identity=-
else
    identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
    if [[ -z "$signing_identity" ]]; then
        if [[ "$signing_mode" == auto || "$signing_mode" == developerID ]]; then
            signing_identity="$(print -r -- "$identities" | /usr/bin/awk '/"Developer ID Application:/{print $2; exit}')"
        fi
        if [[ -z "$signing_identity" && ( "$signing_mode" == auto || "$signing_mode" == dev ) ]]; then
            signing_identity="$(print -r -- "$identities" | /usr/bin/awk '/"Apple Development:|"Mac Developer:/{print $2; exit}')"
        fi
        if [[ -z "$signing_identity" ]]; then
            [[ "$signing_mode" == auto ]] || { mamori_fail "No accessible valid identity for SIGNING_MODE=$signing_mode. Unlock the signing keychain or choose an explicit local identity."; exit 1; }
            signing_identity=-
        fi
    fi
    if [[ "$signing_identity" == - ]]; then
        [[ "$signing_mode" == auto ]] || { mamori_fail 'A certificate identity is required for this signing mode.'; exit 2; }
        signing_mode=adhoc
    elif [[ "$signing_mode" == auto ]]; then
        identity_record="$(print -r -- "$identities" | /usr/bin/awk -v selected="$signing_identity" 'index($0,selected){print; exit}')"
        case "$identity_record" in
            *'"Developer ID Application:'*) signing_mode=developerID ;;
            *'"Apple Development:'*|*'"Mac Developer:'*) signing_mode=dev ;;
            *) mamori_fail 'Cannot determine the selected signing identity. Set SIGNING_MODE=dev or developerID explicitly.'; exit 1 ;;
        esac
    fi
fi

bundle_stage="$(mktemp -d /private/tmp/mamori-bundles.XXXXXX)"
trap 'rm -rf "$bundle_stage"' EXIT
app_dir="$bundle_stage/Mamori.app"
preview_dir="$bundle_stage/Mamori Preview.app"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/ModuleCache"
swift build -c "$configuration" --cache-path "$project_dir/.build/cache" --config-path "$project_dir/.build/config" --security-path "$project_dir/.build/security" --disable-sandbox
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Library/LaunchDaemons"
install -m 755 ".build/$configuration/Mamori" "$app_dir/Contents/MacOS/Mamori"
install -m 755 ".build/$configuration/MamoriGuard" "$app_dir/Contents/MacOS/MamoriGuard"
install -m 644 Resources/Info.plist "$app_dir/Contents/Info.plist"
install -m 644 Resources/com.mamori.guard.plist "$app_dir/Contents/Library/LaunchDaemons/com.mamori.guard.plist"
mkdir -p "$preview_dir/Contents/MacOS" "$preview_dir/Contents/Resources"
install -m 755 ".build/$configuration/Mamori" "$preview_dir/Contents/MacOS/Mamori"
install -m 644 Resources/Info.plist "$preview_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.mamori.preview' "$preview_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Mamori Preview' "$preview_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Mamori Preview' "$preview_dir/Contents/Info.plist"
for bundle in "$app_dir" "$preview_dir"; do
    for asset in Mamori.icns MamoriIcon.png; do
        if [[ -f "Resources/$asset" ]]; then install -m 644 "Resources/$asset" "$bundle/Contents/Resources/$asset"; fi
    done
    # Only strip incidental metadata from disposable, newly assembled build products.
    xattr -cr "$bundle"
done
sign_options=(--force --options runtime --sign "$signing_identity")
if [[ "$signing_mode" == developerID ]]; then sign_options+=(--timestamp); else sign_options+=(--timestamp=none); fi
# Sign nested executable first; never use --deep as a substitute for inside-out signing.
codesign "${sign_options[@]}" --identifier com.mamori.guard "$app_dir/Contents/MacOS/MamoriGuard"
codesign "${sign_options[@]}" --identifier com.mamori.app "$app_dir"
codesign "${sign_options[@]}" --identifier com.mamori.preview "$preview_dir"
mamori_validate_bundles "$app_dir" "$preview_dir"
[[ "$mamori_signing_kind" == "$signing_mode" ]] || { mamori_fail 'The selected certificate does not match SIGNING_MODE.'; exit 1; }
if [[ -n "${SIGNING_TEAM_ID:-}" && "$mamori_team_id" != "$SIGNING_TEAM_ID" ]]; then
    mamori_fail 'The signed Team ID does not match SIGNING_TEAM_ID.'; exit 1
fi
mkdir -p "$output_dir"
# Replace only these generated app copies, so obsolete nested code cannot survive a rebuild.
rm -rf "$output_dir/Mamori.app" "$output_dir/Mamori Preview.app"
ditto --norsrc --noextattr "$app_dir" "$output_dir/Mamori.app"
ditto --norsrc --noextattr "$preview_dir" "$output_dir/Mamori Preview.app"
# Archive from verified staging before File Provider can add metadata.
ditto -c -k --norsrc --noextattr --keepParent "$app_dir" "$output_dir/Mamori.zip"
ditto -c -k --norsrc --noextattr --keepParent "$preview_dir" "$output_dir/Mamori Preview.zip"
print "Built Mamori $mamori_version ($mamori_asset_arch, $mamori_signing_kind) in $output_dir"
case "$signing_mode" in
    adhoc) print 'Ad-hoc build: the real privileged guard is unavailable. Preview always simulates effects.' ;;
    dev) print 'Apple Development build: local helper setup is available after explicit macOS approval. Not a public distribution build.' ;;
    developerID) print 'Developer ID build: notarize before public distribution. Helper setup still requires explicit macOS approval.' ;;
esac
print 'Build validation did not launch either app, register a helper, or change the network.'
