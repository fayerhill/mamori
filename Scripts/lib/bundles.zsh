# Shared validation for assembled apps. This file never launches either executable.
function mamori_fail() {
    print -u2 -- "Mamori: $1"
    return 1
}

function mamori_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

function mamori_check_signature() {
    local signed_path="$1" expected_identifier="$2" info authority
    /usr/bin/codesign --verify --strict "$signed_path" || return 1
    info="$(/usr/bin/codesign -d --verbose=4 "$signed_path" 2>&1)" || return 1
    [[ "$(print -r -- "$info" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$expected_identifier" ]] || {
        mamori_fail "Unexpected signed identifier for $signed_path"; return 1
    }
    [[ "$info" == *'flags='*'(runtime)'* || "$info" == *'flags='*',runtime)'* ]] || {
        mamori_fail "Hardened Runtime is missing from $signed_path"; return 1
    }
    mamori_checked_team=""
    if [[ "$info" == *'Signature=adhoc'* ]]; then
        mamori_checked_kind=adhoc
        return 0
    fi
    /usr/bin/codesign --verify --strict -R="anchor apple generic and identifier \"$expected_identifier\"" "$signed_path" || return 1
    mamori_checked_team="$(print -r -- "$info" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    [[ "$mamori_checked_team" =~ '^[A-Z0-9]{10}$' ]] || {
        mamori_fail "A valid Apple Team ID is required for $signed_path"; return 1
    }
    authority="$(print -r -- "$info" | /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
    case "$authority" in
        'Developer ID Application:'*)
            mamori_checked_kind=developerID
            [[ "$info" == *$'\nTimestamp='* ]] || {
                mamori_fail "A secure timestamp is required for Developer ID builds."; return 1
            }
            ;;
        'Apple Development:'*|'Mac Developer:'*) mamori_checked_kind=dev ;;
        *) mamori_fail "Use Apple Development for local builds or Developer ID Application for distribution."; return 1 ;;
    esac
}

function mamori_validate_bundles() {
    local normal_app="$1" preview_app="$2" normal_info preview_info daemon_info helper
    local preview_kind preview_team helper_kind helper_team normal_arch preview_arch helper_arch key
    normal_info="$normal_app/Contents/Info.plist"
    preview_info="$preview_app/Contents/Info.plist"
    daemon_info="$normal_app/Contents/Library/LaunchDaemons/com.mamori.guard.plist"
    helper="$normal_app/Contents/MacOS/MamoriGuard"
    for key in "$normal_info" "$preview_info" "$daemon_info"; do /usr/bin/plutil -lint "$key" >/dev/null || return 1; done
    [[ "$(mamori_plist_value "$normal_info" CFBundleIdentifier)" == com.mamori.app &&
       "$(mamori_plist_value "$preview_info" CFBundleIdentifier)" == com.mamori.preview &&
       "$(mamori_plist_value "$normal_info" CFBundleExecutable)" == Mamori &&
       "$(mamori_plist_value "$preview_info" CFBundleExecutable)" == Mamori ]] || {
        mamori_fail 'The archives do not contain the expected Mamori applications.'; return 1
    }
    [[ -x "$helper" && ! -L "$helper" ]] || { mamori_fail 'The normal app must embed its helper executable.'; return 1; }
    [[ ! -e "$preview_app/Contents/MacOS/MamoriGuard" && ! -e "$preview_app/Contents/Library/LaunchDaemons" ]] || {
        mamori_fail 'The preview must not contain a privileged helper or service plist.'; return 1
    }
    [[ "$(mamori_plist_value "$daemon_info" Label)" == com.mamori.guard &&
       "$(mamori_plist_value "$daemon_info" BundleProgram)" == Contents/MacOS/MamoriGuard &&
       "$(mamori_plist_value "$daemon_info" MachServices:com.mamori.guard)" == true &&
       "$(mamori_plist_value "$daemon_info" AssociatedBundleIdentifiers:0)" == com.mamori.app ]] || {
        mamori_fail 'The daemon identity or bundle-relative executable path is incorrect.'; return 1
    }
    [[ "$(mamori_plist_value "$daemon_info" MachServices | /usr/bin/awk '/ = /{n++} END{print n+0}')" == 1 ]] || {
        mamori_fail 'Only the Mamori Mach service may be exposed.'; return 1
    }
    for key in Program ProgramArguments KeepAlive RunAtLoad WatchPaths QueueDirectories StartInterval StartCalendarInterval; do
        if mamori_plist_value "$daemon_info" "$key" >/dev/null 2>&1; then
            mamori_fail "The demand-started helper must not define $key."; return 1
        fi
    done
    if mamori_plist_value "$daemon_info" AssociatedBundleIdentifiers:1 >/dev/null 2>&1; then
        mamori_fail 'The helper may be associated only with Mamori.'; return 1
    fi
    mamori_check_signature "$normal_app" com.mamori.app || return 1
    mamori_signing_kind="$mamori_checked_kind"
    mamori_team_id="$mamori_checked_team"
    mamori_check_signature "$helper" com.mamori.guard || return 1
    helper_kind="$mamori_checked_kind"; helper_team="$mamori_checked_team"
    mamori_check_signature "$preview_app" com.mamori.preview || return 1
    preview_kind="$mamori_checked_kind"; preview_team="$mamori_checked_team"
    [[ "$helper_kind" == "$mamori_signing_kind" && "$preview_kind" == "$mamori_signing_kind" &&
       "$helper_team" == "$mamori_team_id" && "$preview_team" == "$mamori_team_id" ]] || {
        mamori_fail 'App, helper, and preview must use the same signing mode and Team ID.'; return 1
    }
    normal_arch="$(/usr/bin/lipo -archs "$normal_app/Contents/MacOS/Mamori")"
    preview_arch="$(/usr/bin/lipo -archs "$preview_app/Contents/MacOS/Mamori")"
    helper_arch="$(/usr/bin/lipo -archs "$helper")"
    [[ "$normal_arch" == "$preview_arch" && "$normal_arch" == "$helper_arch" ]] || {
        mamori_fail 'App, preview, and helper architectures must match.'; return 1
    }
    case "$normal_arch" in
        arm64) mamori_asset_arch=arm64 ;;
        x86_64) mamori_asset_arch=x86_64 ;;
        'arm64 x86_64'|'x86_64 arm64') mamori_asset_arch=universal ;;
        *) mamori_fail "Unsupported architecture: $normal_arch"; return 1 ;;
    esac
    mamori_version="$(mamori_plist_value "$normal_info" CFBundleShortVersionString)"
    [[ "$(mamori_plist_value "$preview_info" CFBundleShortVersionString)" == "$mamori_version" &&
       "$(mamori_plist_value "$preview_info" CFBundleVersion)" == "$(mamori_plist_value "$normal_info" CFBundleVersion)" ]] || {
        mamori_fail 'App and preview versions must match.'; return 1
    }
}
