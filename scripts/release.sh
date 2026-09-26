#!/bin/bash
# `make release x.y.z` in one go:
#
#   1. Checks, changing nothing, that the version is new, main is checked out, clean and not behind
#      origin, gh is logged in and a code-signing identity exists.
#   2. Runs the tests, sets MARKETING_VERSION, builds Release and checks the app: its version and
#      signature, no get-task-allow entitlement, no coverage counters.
#   3. Notarizes it when NOTARY_PROFILE names a `notarytool store-credentials` profile, zips it as
#      build/dist/Uncial-x.y.z.zip and checks that the zip unpacks to a validly signed app with
#      unzip(1) and with ditto.
#   4. Writes the version and the zip's checksum into Casks/uncial.rb, commits the project and the
#      cask as "chore: release x.y.z", tags vx.y.z and pushes main and the tag atomically.
#   5. Creates the GitHub release with the zip and checks that GitHub serves the file the cask pins.
#
# A failure before the push puts the project and the cask back and removes the commit and the tag,
# so the same command starts over. Once the tag is on origin the version is never built again (a new
# zip gets another checksum than the one the tagged cask pins): running the command again completes
# the GitHub release from the zip in build/dist, or reports that the release is complete.
#
# SIGN_IDENTITY ("Developer ID Application: …") reaches xcodebuild through `make build`, for a build
# other Macs open without a Gatekeeper override. GH_REPO (owner/name) overrides the repository gh
# would take from origin; MAKE names the make that runs the tests and the build.

semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
make=${MAKE:-make}
build_dir=${BUILD_DIR:-build}
built_app=$build_dir/Build/Products/Release/Uncial.app
dist=$build_dir/dist
cask=Casks/uncial.rb
project=uncial.xcodeproj/project.pbxproj
# What a failure leaves to undo: checking, prepared (project and cask edited), committed, pushed.
stage=checking
release_commit=

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }

# Succeeds when version $1 is newer than version $2.
newer() {
    local a b i
    IFS=. read -r -a a <<<"$1"
    IFS=. read -r -a b <<<"$2"
    for i in 0 1 2; do
        if [ "${a[i]}" -gt "${b[i]}" ]; then return 0; fi
        if [ "${a[i]}" -lt "${b[i]}" ]; then return 1; fi
    done
    return 1
}

# owner/name of the GitHub repository origin points at.
github_repository() {
    local url
    url=$(git remote get-url origin) || return 1
    url=${url%.git}
    case $url in
    https://github.com/*) echo "${url#https://github.com/}" ;;
    git@github.com:*) echo "${url#git@github.com:}" ;;
    ssh://git@github.com/*) echo "${url#ssh://git@github.com/}" ;;
    *) echo "release: origin ($url) is not on GitHub; set GH_REPO=owner/name" >&2; return 1 ;;
    esac
}

# The object origin's tag vx.y.z names; empty when origin has no such tag.
remote_tag() {
    local line
    line=$(git ls-remote --tags --refs origin "refs/tags/$tag") || return 1
    cut -f 1 <<<"$line"
}

# The newest x.y.z among origin's v tags; empty when there is none.
latest_release() {
    local tags ref candidate latest=
    tags=$(git ls-remote --tags --refs origin) || return 1
    while read -r _ ref; do
        candidate=${ref#refs/tags/v}
        [[ $candidate =~ $semver ]] || continue
        if [ -z "$latest" ] || newer "$candidate" "$latest"; then latest=$candidate; fi
    done <<<"$tags"
    echo "$latest"
}

authority() {
    local details
    details=$(codesign -dvv "$1" 2>&1) || return 1
    details=$(sed -n 's/^Authority=//p' <<<"$details")
    echo "${details%%$'\n'*}"
}

# Checks a built or unpacked Uncial.app before it goes out.
check_app() {
    local app=$1 found bundle entitlements executable commands
    found=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist") || die "cannot read the version of $app"
    [ "$found" = "$version" ] || die "$app is version $found, not $version"
    codesign --verify --deep --strict "$app" || die "the signature of $app does not verify"
    for bundle in "$app" "$app/Contents/PlugIns/UncialQuickLook.appex" "$app/Contents/PlugIns/UncialThumbnail.appex"; do
        # Xcode adds the debugger's entitlement to development-signed builds unless
        # CODE_SIGN_INJECT_BASE_ENTITLEMENTS is NO, as the project's Release configuration sets
        # (1.0.0 and 1.0.1 shipped with it). Entitlements that cannot be read fail the release too.
        entitlements=$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null) || die "cannot read the entitlements of $bundle"
        [[ $entitlements != *com.apple.security.get-task-allow* ]] || die "$bundle carries com.apple.security.get-task-allow"
        # Coverage counters come with the scheme's code coverage (1.1.2 and 1.1.3 shipped with them).
        executable=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$bundle/Contents/Info.plist") || die "cannot read the executable name of $bundle"
        commands=$(xcrun otool -l "$bundle/Contents/MacOS/$executable") || die "cannot read $bundle/Contents/MacOS/$executable"
        [[ $commands != *__llvm_prf* ]] || die "$bundle/Contents/MacOS/$executable carries coverage counters (__llvm_prf)"
    done
}

# ditto keeps extended attributes, resource forks and ACLs as AppleDouble `._` entries unless told
# not to, and unzip(1) writes those out as files inside the bundle, which breaks its signature.
zip_app() { ditto -c -k --norsrc --noextattr --noacl --keepParent "$1" "$2"; }

check_zip() {
    local entries unpacked=$dist/check
    entries=$(zipinfo -1 "$zip") || die "cannot list $zip"
    if grep -Eq '(^|/)\._' <<<"$entries"; then die "$zip holds AppleDouble ._ entries"; fi
    rm -rf "$unpacked"
    mkdir -p "$unpacked/unzip" "$unpacked/ditto"
    unzip -q "$zip" -d "$unpacked/unzip" || die "unzip cannot unpack $zip"
    ditto -x -k "$zip" "$unpacked/ditto" || die "ditto cannot unpack $zip"
    check_app "$unpacked/unzip/Uncial.app"
    check_app "$unpacked/ditto/Uncial.app"
    rm -rf "$unpacked"
}

# Checks that GitHub serves the file the cask pins.
verify_asset() {
    local expected=sha256:$1 digest scratch
    digest=$(gh api "repos/$GH_REPO/releases/tags/$tag" --jq ".assets[] | select(.name == \"$asset\") | .digest") || die "cannot read $tag from GitHub"
    if [ -z "$digest" ] || [ "$digest" = null ]; then
        # GitHub has no digest for the asset: compare a download.
        scratch=$(mktemp -d)
        gh release download "$tag" --pattern "$asset" --dir "$scratch" || die "cannot download $asset"
        digest=sha256:$(sha256 "$scratch/$asset")
        rm -rf "$scratch"
    fi
    [ "$digest" = "$expected" ] || die "GitHub serves $asset as $digest but the cask pins $expected, so brew refuses it; if $zip matches the cask, 'gh release upload $tag $zip --clobber', otherwise release a new version"
    echo "GitHub serves $asset with the checksum the cask pins."
}

finished() {
    local url
    url=$(gh release view "$tag" --json url --jq .url 2>/dev/null) || url=https://github.com/$GH_REPO/releases/tag/$tag
    step "Uncial $version is released"
    echo "$url"
    echo "Homebrew reads the cask from main: brew update && brew upgrade --cask uncial"
}

on_exit() {
    local status=$?
    set +e
    rm -rf "$dist/check"
    [ "$status" -ne 0 ] || return 0
    case $stage in
    prepared)
        git checkout -q -- "$project" "$cask"
        echo "release: put $project and $cask back; nothing was committed" >&2
        ;;
    committed)
        if [ "$(git rev-parse HEAD)" = "$release_commit" ]; then
            git tag -d "$tag" >/dev/null 2>&1
            git reset -q --soft HEAD^
            git reset -q -- "$project" "$cask"
            git checkout -q -- "$project" "$cask"
            echo "release: removed the release commit and the tag; nothing was published" >&2
        else
            echo "release: HEAD moved, so the release commit ${release_commit:0:7} and the tag $tag are left as they are" >&2
        fi
        ;;
    pushed)
        echo "release: $tag is on origin but its GitHub release is not complete; run 'make release $version' again" >&2
        ;;
    esac
}

# vx.y.z is on origin already: complete its GitHub release with the zip that was tagged. Never
# builds: a new zip would not match the checksum the tagged cask pins.
finish() {
    local published=$1 ours cask_text pinned_version pinned draft assets=
    step "$tag is on origin: completing its GitHub release"
    ours=$(git rev-parse -q --verify "refs/tags/$tag") || ours=
    if [ -z "$ours" ]; then
        git fetch -q origin "refs/tags/$tag:refs/tags/$tag" || die "cannot fetch $tag"
    elif [ "$ours" != "$published" ]; then
        die "the local tag $tag is not origin's; delete it with 'git tag -d $tag' and run again"
    fi
    cask_text=$(git show "$tag:$cask") || die "$tag has no $cask"
    pinned_version=$(sed -n 's/^  version "\(.*\)"$/\1/p' <<<"$cask_text")
    pinned=$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' <<<"$cask_text")
    [ "$pinned_version" = "$version" ] || die "the cask at $tag is for ${pinned_version:-no version}, not $version"
    if draft=$(gh release view "$tag" --json isDraft --jq .isDraft 2>/dev/null); then
        assets=$(gh release view "$tag" --json assets --jq '.assets[].name') || die "cannot list the assets of $tag"
    else
        draft=
    fi
    if ! grep -Fqx "$asset" <<<"$assets"; then
        [ -f "$zip" ] || die "GitHub has no $asset for $tag and $zip is gone; a new zip would not match the cask, so release a new version"
        [ "$(sha256 "$zip")" = "$pinned" ] || die "$zip does not match the cask at $tag; release a new version"
        if [ -z "$draft" ]; then
            step "Creating the GitHub release"
            gh release create "$tag" "$zip" --verify-tag --title "Uncial $version" --generate-notes
        else
            step "Uploading $asset"
            gh release upload "$tag" "$zip"
        fi
    fi
    if [ "$draft" = true ]; then
        step "Publishing the draft release"
        gh release edit "$tag" --draft=false
    fi
    verify_asset "$pinned"
    finished
}

# vx.y.z is new: test, build, package, commit, tag, push and release it.
release() {
    local branch changes current latest behind identities ahead sha pushed
    branch=$(git symbolic-ref -q --short HEAD) || branch="a detached HEAD"
    [ "$branch" = main ] || die "releases are made from main, not $branch"
    # Untracked files count: the project's synchronized groups build every file in their folders.
    changes=$(git status --porcelain --untracked-files=normal)
    [ -z "$changes" ] || die "commit or stash these changes first:"$'\n'"$changes"
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        die "there is a local tag $tag that origin lacks (left by an interrupted run?); delete it with 'git tag -d $tag' and run again"
    fi
    if gh release view "$tag" >/dev/null 2>&1; then
        die "GitHub has a release $tag but origin has no such tag; delete the release on GitHub first"
    fi
    current=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$project" | sort -u)
    [[ $current =~ $semver ]] || die "$project has no single MARKETING_VERSION: $current"
    if newer "$current" "$version"; then die "the project is at $current already"; fi
    latest=$(latest_release) || die "cannot read origin's tags"
    if [ -n "$latest" ] && ! newer "$version" "$latest"; then die "$version is not newer than the latest release, $latest"; fi
    git fetch -q origin main || die "cannot fetch origin"
    behind=$(git rev-list --count HEAD..origin/main)
    [ "$behind" -eq 0 ] || die "origin/main has $behind commit(s) that main lacks; run 'git pull --rebase' and run again"
    identities=$(security find-identity -v -p codesigning) || die "cannot list the code-signing identities"
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        grep -Fq "$SIGN_IDENTITY" <<<"$identities" || die "no valid code-signing identity matches '$SIGN_IDENTITY'"
    elif grep -q ' 0 valid identities found' <<<"$identities"; then
        die "no valid code-signing identity in the keychain"
    fi
    echo "Releasing Uncial $version from $(git rev-parse --short HEAD) (project at $current, latest release ${latest:-none})."
    ahead=$(git log --format='  %h %s' origin/main..HEAD)
    [ -z "$ahead" ] || echo "These commits go to origin with it:"$'\n'"$ahead"

    step "Testing"
    "$make" --no-print-directory test

    step "Building $version"
    stage=prepared
    if [ "$current" != "$version" ]; then
        sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $version;/" "$project"
    fi
    "$make" --no-print-directory build CONFIG=Release BUILD_DIR="$build_dir"
    check_app "$built_app"
    echo "$built_app: version $version, signed by $(authority "$built_app"), no get-task-allow, no coverage counters"

    step "Packaging"
    mkdir -p "$dist"
    rm -rf "$dist/Uncial.app" "$zip"
    ditto "$built_app" "$dist/Uncial.app"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        step "Notarizing"
        zip_app "$dist/Uncial.app" "$zip"
        xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$dist/Uncial.app"
        rm "$zip"
    fi
    zip_app "$dist/Uncial.app" "$zip"
    check_zip
    sha=$(sha256 "$zip")
    sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask"
    grep -Fqx "  version \"$version\"" "$cask" && grep -Fqx "  sha256 \"$sha\"" "$cask" || die "cannot write the version and checksum into $cask"
    echo "$zip: sha256 $sha, unpacks to a valid app with unzip and with ditto"

    step "Committing, tagging and pushing"
    git fetch -q origin main || die "cannot fetch origin"
    behind=$(git rev-list --count HEAD..origin/main)
    [ "$behind" -eq 0 ] || die "origin/main got $behind new commit(s) meanwhile; run 'git pull --rebase' and run again"
    git commit -q -m "chore: release $version" -- "$project" "$cask"
    release_commit=$(git rev-parse HEAD)
    stage=committed
    git tag -a "$tag" -m "Uncial $version"
    if ! git push --atomic origin "HEAD:refs/heads/main" "refs/tags/$tag"; then
        # The push can fail after origin took it (a dropped connection): origin decides.
        if ! pushed=$(remote_tag); then
            stage=unknown
            die "the push failed and origin cannot tell whether it took $tag; when 'git ls-remote origin refs/tags/$tag' shows it, run 'make release $version' again, otherwise remove the release commit and 'git tag -d $tag'"
        fi
        [ "$pushed" = "$(git rev-parse "refs/tags/$tag")" ] || die "origin rejected the push"
    fi
    stage=pushed

    step "Creating the GitHub release"
    gh release create "$tag" "$zip" --verify-tag --title "Uncial $version" --generate-notes
    verify_asset "$sha"
    stage=released
    finished
}

main() {
    set -euo pipefail
    cd "$(dirname "$0")/.."
    if [ $# -ne 1 ] || ! [[ $1 =~ $semver ]]; then
        echo "usage: make release x.y.z" >&2
        exit 2
    fi
    version=$1
    tag=v$version
    asset=Uncial-$version.zip
    zip=$dist/$asset
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    step "Checking"
    if [ -z "${GH_REPO:-}" ]; then GH_REPO=$(github_repository); fi
    export GH_REPO
    gh auth status >/dev/null 2>&1 || die "gh is not logged in; run 'gh auth login'"
    local published
    published=$(remote_tag) || die "cannot read origin's tags"
    if [ -n "$published" ]; then
        finish "$published"
    else
        release
    fi
}

# Sourcing the script defines its functions without running it.
[ "${BASH_SOURCE[0]}" != "$0" ] || main "$@"
