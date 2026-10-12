#!/bin/zsh
set -euo pipefail

# Synthetic signed fixtures only. Never launch code, register a helper, or touch PF.
project_dir="${0:A:h:h}"
source "$project_dir/Scripts/lib/bundles.zsh"
fixture_root="$(mktemp -d /private/tmp/mamori-bundle-tests.XXXXXX)"
trap 'rm -rf "$fixture_root"' EXIT
normal_app="$fixture_root/base/Mamori.app"
preview_app="$fixture_root/base/Mamori Preview.app"
mkdir -p "$normal_app/Contents/MacOS" "$normal_app/Contents/Library/LaunchDaemons" "$preview_app/Contents/MacOS"
print 'int main(void) { return 0; }' > "$fixture_root/fixture.c"
xcrun clang "$fixture_root/fixture.c" -o "$fixture_root/fixture"
for bundle in "$normal_app" "$preview_app"; do
    install -m 755 "$fixture_root/fixture" "$bundle/Contents/MacOS/Mamori"
    install -m 644 "$project_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"
done
install -m 755 "$fixture_root/fixture" "$normal_app/Contents/MacOS/MamoriGuard"
install -m 644 "$project_dir/Resources/com.mamori.guard.plist" "$normal_app/Contents/Library/LaunchDaemons/com.mamori.guard.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.mamori.preview' "$preview_app/Contents/Info.plist"
sign_options=(--force --options runtime --timestamp=none --sign -)
codesign "${sign_options[@]}" --identifier com.mamori.guard "$normal_app/Contents/MacOS/MamoriGuard" >/dev/null 2>&1
codesign "${sign_options[@]}" --identifier com.mamori.app "$normal_app" >/dev/null 2>&1
codesign "${sign_options[@]}" --identifier com.mamori.preview "$preview_app" >/dev/null 2>&1
mamori_validate_bundles "$normal_app" "$preview_app"
[[ "$mamori_signing_kind" == adhoc ]] || exit 1
print 'PASS: valid ad-hoc bundle pair'

function prepare_case() {
    local name="$1"
    case_dir="$fixture_root/$name"
    ditto --norsrc --noextattr "$fixture_root/base" "$case_dir"
    case_normal="$case_dir/Mamori.app"
    case_preview="$case_dir/Mamori Preview.app"
}
function expect_rejected() {
    local name="$1"
    if mamori_validate_bundles "$case_normal" "$case_preview" > "$fixture_root/rejection.txt" 2>&1; then
        print -u2 "FAIL: $name was accepted"
        exit 1
    fi
    print "PASS: $name rejected"
}
prepare_case tampered-helper
print 'tampered' >> "$case_normal/Contents/MacOS/MamoriGuard"
expect_rejected 'modified helper executable'

prepare_case absolute-program
/usr/libexec/PlistBuddy -c 'Set :BundleProgram /tmp/untrusted-helper' "$case_normal/Contents/Library/LaunchDaemons/com.mamori.guard.plist"
codesign "${sign_options[@]}" --identifier com.mamori.app "$case_normal" >/dev/null 2>&1
expect_rejected 'absolute daemon executable path'

prepare_case auto-start
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$case_normal/Contents/Library/LaunchDaemons/com.mamori.guard.plist"
codesign "${sign_options[@]}" --identifier com.mamori.app "$case_normal" >/dev/null 2>&1
expect_rejected 'unrequested daemon auto-start'

prepare_case preview-helper
install -m 755 "$fixture_root/fixture" "$case_preview/Contents/MacOS/MamoriGuard"
codesign "${sign_options[@]}" --identifier com.mamori.preview "$case_preview" >/dev/null 2>&1
expect_rejected 'privileged helper in preview'

prepare_case helper-identity
codesign "${sign_options[@]}" --identifier com.other.helper "$case_normal/Contents/MacOS/MamoriGuard" >/dev/null 2>&1
codesign "${sign_options[@]}" --identifier com.mamori.app "$case_normal" >/dev/null 2>&1
expect_rejected 'unexpected helper signing identifier'
print 'All six synthetic bundle checks passed. No fixture executable was launched.'
