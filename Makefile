DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CONFIG ?= Release
BUILD_DIR ?= build
XCODEBUILD = xcodebuild -project uncial.xcodeproj -scheme uncial -derivedDataPath $(BUILD_DIR)
APP = $(BUILD_DIR)/Build/Products/$(CONFIG)/Uncial.app
# `make release 1.2.0` and `make bump 1.2.0` take the version as the goal after theirs (or
# VERSION=1.2.0); the version goal itself does nothing.
ifneq ($(filter release bump,$(firstword $(MAKECMDGOALS))),)
  GOAL_VERSION := $(or $(word 2,$(MAKECMDGOALS)),$(if $(filter command line,$(origin VERSION)),$(VERSION)))
  $(if $(word 2,$(MAKECMDGOALS)),$(eval $(word 2,$(MAKECMDGOALS)):;@:))
endif
# SIGN_IDENTITY=- signs ad hoc, for a build from source without the project team's certificate. Set it
# to a "Developer ID Application: …" identity for a build other Macs can open without a Gatekeeper
# override; NOTARY_PROFILE (a `notarytool store-credentials` profile) notarizes it.
SIGN_FLAGS = $(if $(SIGN_IDENTITY),CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" OTHER_CODE_SIGN_FLAGS=--timestamp,)

.PHONY: build test core-test install uninstall icon highlight mermaid clean bump release

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

mermaid:
	scripts/build-mermaid.sh

# Sets MARKETING_VERSION; `make release` does it too.
bump:
	@echo "$(GOAL_VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "usage: make bump x.y.z" >&2; exit 2; }
	sed -i '' 's/MARKETING_VERSION = .*;/MARKETING_VERSION = $(GOAL_VERSION);/' uncial.xcodeproj/project.pbxproj
	@echo "Project version is now $(GOAL_VERSION)."

# Tests, builds, zips and publishes a release, cask included; a second run completes a release a
# failure interrupted (scripts/release.sh).
release:
	@BUILD_DIR="$(BUILD_DIR)" scripts/release.sh $(GOAL_VERSION)

clean:
	rm -rf $(BUILD_DIR)
