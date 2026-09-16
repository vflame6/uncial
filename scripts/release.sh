#!/bin/sh
# Packages a Release build for a GitHub release and points the Homebrew cask at it.
#
#   scripts/release.sh package <version> <path/to/Uncial.app>
#       Copies the app to build/dist, notarizes and staples it when NOTARY_PROFILE names a
#       `notarytool store-credentials` profile, zips it as build/dist/Uncial-<version>.zip and
#       writes the version and checksum into Casks/uncial.rb.
#   scripts/release.sh publish <version>
#       Commits the cask, tags v<version>, pushes, and creates the GitHub release with the zip.
set -eu

command=$1
version=$2
dist=build/dist
zip="$dist/Uncial-$version.zip"
cask=Casks/uncial.rb

case "$command" in
package)
    app=$3
    rm -rf "$dist"
    mkdir -p "$dist"
    cp -R "$app" "$dist/Uncial.app"
    app="$dist/Uncial.app"
    plist_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
    if [ "$plist_version" != "$version" ]; then
        echo "The app reports version $plist_version, not $version; run 'make bump VERSION=$version' and rebuild." >&2
        exit 1
    fi
    codesign --verify --deep --strict "$app"
    echo "Signed as: $(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        ditto -c -k --keepParent "$app" "$zip"
        xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$app"
        rm "$zip"
    fi
    ditto -c -k --keepParent "$app" "$zip"
    sha=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)
    sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask"
    echo "Packaged $zip"
    echo "sha256 $sha"
    echo "Updated $cask; review it, then 'make publish' to tag v$version and create the GitHub release."
    ;;
publish)
    if [ ! -f "$zip" ]; then
        echo "$zip is missing; run 'make release' first." >&2
        exit 1
    fi
    git add "$cask"
    git commit -m "chore: release $version"
    git tag "v$version"
    git push --follow-tags
    gh release create "v$version" "$zip" --title "Uncial $version" --generate-notes
    ;;
*)
    echo "usage: scripts/release.sh package <version> <app> | publish <version>" >&2
    exit 2
    ;;
esac
