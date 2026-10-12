#!/bin/zsh
set -euo pipefail

# Package existing archives. Notarization is opt-in; no app or helper is launched.
project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/Scripts/lib/bundles.zsh"
make_dmg=false
notary_profile=""
while (( $# > 0 )); do
    case "$1" in
        --dmg) make_dmg=true; shift ;;
        --notarize)
            (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || { mamori_fail '--notarize requires an existing notarytool keychain-profile name.'; exit 2; }
            notary_profile="$2"; shift 2 ;;
        *) print -u2 'Usage: ./Scripts/release.sh [--dmg] [--notarize KEYCHAIN_PROFILE]'; exit 2 ;;
    esac
done
for archive in 'build/Mamori.zip' 'build/Mamori Preview.zip'; do
    [[ -f "$archive" ]] || { mamori_fail "Missing $archive. Build the final source first."; exit 1; }
done
release_stage="$(mktemp -d /private/tmp/mamori-release.XXXXXX)"
trap 'rm -rf "$release_stage"' EXIT
normal_dir="$release_stage/Mamori"
preview_dir="$release_stage/Mamori Preview"
mkdir -p "$normal_dir" "$preview_dir" "$release_stage/assets"
ditto -x -k 'build/Mamori.zip' "$normal_dir"
ditto -x -k 'build/Mamori Preview.zip' "$preview_dir"
normal_app="$normal_dir/Mamori.app"
preview_app="$preview_dir/Mamori Preview.app"
mamori_validate_bundles "$normal_app" "$preview_app"
if [[ "$mamori_signing_kind" == dev ]]; then
    mamori_fail 'Apple Development builds are for this developer only, not public downloads. Use SIGNING_MODE=developerID for distribution, or SIGNING_MODE=adhoc for a clearly labeled limited preview.'
    exit 1
fi
if [[ -n "$notary_profile" && "$mamori_signing_kind" != developerID ]]; then
    mamori_fail 'Notarization requires a Developer ID Application build.'
    exit 1
fi

notarized=false
function submit_for_notarization() {
    local submitted_path="$1" label="$2" response="$release_stage/notary-$2.plist"
    mkdir -p "$project_dir/build/notarization"
    if ! xcrun notarytool submit "$submitted_path" --keychain-profile "$notary_profile" --wait --timeout 30m --output-format plist > "$response"; then
        [[ ! -s "$response" ]] || install -m 600 "$response" "$project_dir/build/notarization/notary-$label.plist"
        mamori_fail "Notarization did not complete for $label. No release assets were updated."
        return 1
    fi
    install -m 600 "$response" "$project_dir/build/notarization/notary-$label.plist"
    [[ "$(/usr/bin/plutil -extract status raw -o - "$response")" == Accepted ]] || {
        mamori_fail "Apple did not accept $label. Inspect build/notarization/notary-$label.plist; do not distribute."; return 1
    }
}
if [[ -n "$notary_profile" ]]; then
    submission_dir="$release_stage/submission"
    mkdir -p "$submission_dir"
    ditto --norsrc --noextattr "$normal_app" "$submission_dir/Mamori.app"
    ditto --norsrc --noextattr "$preview_app" "$submission_dir/Mamori Preview.app"
    ditto -c -k --norsrc --noextattr "$submission_dir" "$release_stage/notary-apps.zip"
    submit_for_notarization "$release_stage/notary-apps.zip" apps
    for app_bundle in "$normal_app" "$preview_app"; do
        xcrun stapler staple "$app_bundle"
        xcrun stapler validate "$app_bundle"
        /usr/sbin/spctl --assess --type execute "$app_bundle"
    done
    mamori_validate_bundles "$normal_app" "$preview_app"
    notarized=true
fi

cat > "$release_stage/Quick Start.txt" <<'GUIDE'
MAMORI

Install without Terminal
1. Open the ZIP or double-click the disk image.
2. Drag the app you want into Applications.
3. Open it from Applications. Click the shield in the menu bar.
   Xcode and Homebrew are not needed to run these downloads.

Choose an app
- Mamori.app: real keep-awake controls and read-only GlobalProtect observation.
- Mamori Preview.app: always a simulation of VPN, firewall, keep-awake, and
  application-quit effects. Its installed-app picker is read-only.
  The preview contains no privileged background-service executable.

Use and quit
Keep-awake starts off and is independent of the network guard. It prevents idle
system sleep while enabled, allowing display sleep or lock; it does not defeat
lid closure or explicit sleep, and cannot guarantee remote AI job completion.
Use Restore & Quit to end active behavior while retaining the app and settings.
Settings > Complete Uninstall requests confirmation, restores the owned network
resources, unregisters the service, then permanently deletes this running app
and this user's Mamori data. It does not use Trash or erase OS records, other
app copies, or source code. Failed cleanup stays visible. Preview simulates this
action and never installs a service or deletes an app.

Requirements
macOS 14 or later. The download filename identifies the processor architecture:
arm64 = Apple silicon; x86_64 = Intel; universal = both.
GUIDE
if [[ "$mamori_signing_kind" == adhoc ]]; then
    cat >> "$release_stage/Quick Start.txt" <<'GUIDE'

DEVELOPMENT PREVIEW — AD-HOC SIGNED, NOT NOTARIZED
The normal app cannot install or activate the privileged network guard in this
build. Automatic app quitting requires an armed guard and is unavailable here.
The presence of a VPN connection is not evidence of firewall protection.
macOS may block the app. If you trust the source, use Apple's documented first-
launch controls when available. A managed Mac may not permit an override.
Never disable Gatekeeper globally or remove quarantine through Terminal.
Apple's instructions: https://support.apple.com/102445
GUIDE
else
    cat >> "$release_stage/Quick Start.txt" <<'GUIDE'

DEVELOPER ID BUILD
The app and embedded helper have matching Apple signing identities. To use the
network guard, configure its supported GlobalProtect connection, explicitly
install the background service in Mamori, and approve it in macOS Settings.
Signing and notarization do not verify packet protection or VPN compatibility.
Use only after separately controlled validation of your exact VPN environment.
The app never automatically installs its helper or reconnects a VPN.
GUIDE
    if $notarized; then
        print 'Apple notarization was accepted; the app tickets were stapled and validated.' >> "$release_stage/Quick Start.txt"
    else
        print 'This Developer ID build has NOT been notarized. It is not ready for general distribution.' >> "$release_stage/Quick Start.txt"
    fi
fi
for package_dir in "$normal_dir" "$preview_dir"; do
    install -m 644 "$release_stage/Quick Start.txt" "$package_dir/Quick Start.txt"
done
assets_dir="$release_stage/assets"
normal_name="Mamori-macOS-$mamori_asset_arch.zip"
preview_name="Mamori-Preview-macOS-$mamori_asset_arch.zip"
ditto -c -k --norsrc --noextattr --keepParent "$normal_dir" "$assets_dir/$normal_name"
ditto -c -k --norsrc --noextattr --keepParent "$preview_dir" "$assets_dir/$preview_name"
asset_names=("$normal_name" "$preview_name")
if $make_dmg; then
    [[ -x /usr/bin/hdiutil ]] || { mamori_fail 'hdiutil is required for --dmg.'; exit 1; }
    disk_dir="$release_stage/disk"
    mkdir -p "$disk_dir"
    ditto --norsrc --noextattr "$normal_app" "$disk_dir/Mamori.app"
    ditto --norsrc --noextattr "$preview_app" "$disk_dir/Mamori Preview.app"
    install -m 644 "$release_stage/Quick Start.txt" "$disk_dir/Quick Start.txt"
    ln -s /Applications "$disk_dir/Applications"
    disk_name="Mamori-macOS-$mamori_asset_arch.dmg"
    hdiutil create -quiet -srcfolder "$disk_dir" -volname Mamori -format UDZO "$assets_dir/$disk_name"
    if [[ "$mamori_signing_kind" == developerID ]]; then
        disk_identity="${SIGNING_IDENTITY:-$(codesign -dvv "$normal_app" 2>&1 | /usr/bin/awk -F= '/^Authority=/{print $2; exit}')}"
        codesign --force --timestamp --sign "$disk_identity" "$assets_dir/$disk_name"
        codesign --verify --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"$mamori_team_id\"" "$assets_dir/$disk_name"
        if $notarized; then
            submit_for_notarization "$assets_dir/$disk_name" dmg
            xcrun stapler staple "$assets_dir/$disk_name"
            xcrun stapler validate "$assets_dir/$disk_name"
        fi
    fi
    asset_names+=("$disk_name")
fi
cat > "$assets_dir/RELEASE-INFO.txt" <<INFO
Mamori version: $mamori_version
Architecture: $mamori_asset_arch
Signing mode: $mamori_signing_kind
Notarized and stapled by this packaging run: $notarized
Packaging validates signatures and structure, not real VPN enforcement.
INFO
asset_names+=(RELEASE-INFO.txt)
(
    cd "$assets_dir"
    shasum -a 256 "${asset_names[@]}" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
output_dir="$project_dir/build/release"
mkdir -p "$output_dir"
for asset in "${asset_names[@]}" SHA256SUMS; do install -m 644 "$assets_dir/$asset" "$output_dir/$asset"; done
print "Prepared Mamori $mamori_version ($mamori_signing_kind, notarized=$notarized) in $output_dir"
print 'Upload only the assets listed in the current SHA256SUMS and SHA256SUMS itself.'
print 'Packaging did not launch an app, register a helper, or change network settings.'
