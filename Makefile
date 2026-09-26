DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CONFIG ?= Release
BUILD_DIR ?= build
XCODEBUILD = xcodebuild -project uncial.xcodeproj -scheme uncial -derivedDataPath $(BUILD_DIR)
APP = $(BUILD_DIR)/Build/Products/$(CONFIG)/Uncial.app
# The version comes from the project (MARKETING_VERSION); `make bump VERSION=x.y.z` changes it.
VERSION ?= $(shell sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' uncial.xcodeproj/project.pbxproj | head -1)
# Set SIGN_IDENTITY to a "Developer ID Application: …" identity for a build other Macs can open
# without a Gatekeeper override; NOTARY_PROFILE (a `notarytool store-credentials` profile) notarizes it.
SIGN_FLAGS = $(if $(SIGN_IDENTITY),CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" OTHER_CODE_SIGN_FLAGS=--timestamp,)

.PHONY: build test core-test install uninstall icon highlight clean bump release publish

# No coverage instrumentation in a build for use: the auto-created scheme gathers coverage when
# testing and so sets CLANG_COVERAGE_MAPPING for every build of the scheme, which put `__llvm_prf`
# counters (and a `default.profraw` write on exit) into the released 1.1.2 and 1.1.3.
build:
	$(XCODEBUILD) -configuration $(CONFIG) build CLANG_COVERAGE_MAPPING=NO ENABLE_CODE_COVERAGE=NO $(SIGN_FLAGS)

core-test:
	cd Packages/UncialCore && swift test

test: core-test
	$(XCODEBUILD) -configuration Debug test -only-testing:uncialTests

install: build
	rm -rf /Applications/Uncial.app
	cp -R "$(APP)" /Applications/Uncial.app
	open -a /Applications/Uncial.app --background
	qlmanage -r
	qlmanage -r cache
	-killall -KILL com.apple.quicklook.ThumbnailsAgent 2>/dev/null
	@echo "Installed /Applications/Uncial.app."
	@echo "If Space in Finder still shows plain text, enable 'Uncial Quick Look' and"
	@echo "'Uncial Thumbnails' under System Settings > General > Login Items & Extensions > Quick Look."

uninstall:
	rm -rf /Applications/Uncial.app
	qlmanage -r

icon:
	swift scripts/make-icon.swift static/icon.png uncial/Assets.xcassets/AppIcon.appiconset

highlight:
	scripts/build-highlight.sh

# Release: `make bump VERSION=1.1.0`, commit, `make release` (build, notarize if NOTARY_PROFILE is
# set, zip, update the cask), then `make publish` (commit the cask, tag, push, GitHub release).
bump:
	@test -n "$(VERSION)" || (echo "make bump VERSION=x.y.z" && exit 1)
	sed -i '' 's/MARKETING_VERSION = .*;/MARKETING_VERSION = $(VERSION);/' uncial.xcodeproj/project.pbxproj
	@echo "Project version is now $(VERSION)."

release: build
	scripts/release.sh package "$(VERSION)" "$(APP)"

publish:
	scripts/release.sh publish "$(VERSION)"

clean:
	rm -rf $(BUILD_DIR)
