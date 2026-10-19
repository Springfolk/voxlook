APP := build/Build/Products/Release/VoxLook.app
DEST ?= /Applications

.PHONY: all project build install uninstall test clean

all: build

project:
	xcodegen generate

build: project
	xcodebuild -project VoxLook.xcodeproj -scheme VoxLook -configuration Release \
		-derivedDataPath build -allowProvisioningUpdates -quiet build

# Copies the app, registers both extensions and resets Quick Look's caches.
install: build
	rm -rf "$(DEST)/VoxLook.app"
	cp -R "$(APP)" "$(DEST)/"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(DEST)/VoxLook.app"
	pluginkit -a "$(DEST)/VoxLook.app/Contents/PlugIns/VoxLookPreview.appex"
	pluginkit -a "$(DEST)/VoxLook.app/Contents/PlugIns/VoxLookThumbnail.appex"
	qlmanage -r >/dev/null && qlmanage -r cache >/dev/null
	@echo "Installed. Select a .vox file in Finder and press Space."

uninstall:
	pluginkit -r "$(DEST)/VoxLook.app/Contents/PlugIns/VoxLookPreview.appex" || true
	pluginkit -r "$(DEST)/VoxLook.app/Contents/PlugIns/VoxLookThumbnail.appex" || true
	rm -rf "$(DEST)/VoxLook.app"
	qlmanage -r >/dev/null && qlmanage -r cache >/dev/null

test:
	swift test

clean:
	rm -rf build .build VoxLook.xcodeproj
