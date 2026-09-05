DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CONFIG ?= Release
BUILD_DIR ?= build
XCODEBUILD = xcodebuild -project uncial.xcodeproj -scheme uncial -derivedDataPath $(BUILD_DIR)
APP = $(BUILD_DIR)/Build/Products/$(CONFIG)/Uncial.app

.PHONY: build test core-test install uninstall icon clean

build:
	$(XCODEBUILD) -configuration $(CONFIG) build

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
	@echo "Installed /Applications/Uncial.app."
	@echo "If Space in Finder still shows plain text, enable 'Uncial Quick Look' under"
	@echo "System Settings > General > Login Items & Extensions > Quick Look."

uninstall:
	rm -rf /Applications/Uncial.app
	qlmanage -r

icon:
	swift scripts/make-icon.swift uncial/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(BUILD_DIR)
