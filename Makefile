APP := build/Build/Products/Release/VoxLook.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all project build install uninstall dist test clean

all: build

project:
	xcodegen generate

build: project
	xcodebuild -project VoxLook.xcodeproj -scheme VoxLook -configuration Release \
		-derivedDataPath build -allowProvisioningUpdates -quiet build

# Installs the local build through the same script as the one-line installer.
# The build product is unregistered after: two registered copies of the app
# confuse Spotlight about which importer to load.
install: build
	./install.sh --from "$(APP)"
	$(LSREGISTER) -u "$(APP)"

uninstall:
	./install.sh --uninstall

# Ad-hoc signed, universal zip: what the GitHub release ships.
dist: project
	xcodebuild -project VoxLook.xcodeproj -scheme VoxLook -configuration Release \
		-derivedDataPath build/dist ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet build
	ditto -c -k --keepParent build/dist/Build/Products/Release/VoxLook.app build/VoxLook.zip
	-$(LSREGISTER) -u build/dist/Build/Products/Release/VoxLook.app
	@echo build/VoxLook.zip

test:
	swift test

clean:
	rm -rf build .build VoxLook.xcodeproj
