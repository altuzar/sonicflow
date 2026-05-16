# SonicFlow — build the SwiftPM executable, wrap in a .app bundle, ad-hoc sign, run.

APP_NAME := SonicFlow
BUNDLE_ID := com.sonicflow.app
CONFIG := release
BUILD_DIR := .build
APP_BUNDLE := build/$(APP_NAME).app
EXECUTABLE := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
INFO_PLIST := Sources/SonicFlow/Resources/Info.plist
ENTITLEMENTS := Sources/SonicFlow/Resources/SonicFlow.entitlements

# Use Xcode's Swift toolchain (full SDK + frameworks) when available.
XCODE_DEV := $(shell xcode-select -p 2>/dev/null)
ifneq ($(XCODE_DEV),)
SWIFT := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift
else
SWIFT := swift
endif

.PHONY: build bundle sign run debug clean

build:
	$(SWIFT) build -c $(CONFIG)

bundle: build icon
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/Icon/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@touch $(APP_BUNDLE)/Contents/PkgInfo
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo

icon:
	@if [ ! -f Resources/Icon/AppIcon.icns ] || [ Resources/Icon/AppIcon.svg -nt Resources/Icon/AppIcon.icns ]; then \
		echo "Rendering AppIcon..."; \
		mkdir -p Resources/Icon/AppIcon.iconset; \
		for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
		            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
		            "512:512x512" "1024:512x512@2x"; do \
			size="$${spec%%:*}"; name="$${spec##*:}"; \
			rsvg-convert -w "$$size" -h "$$size" Resources/Icon/AppIcon.svg \
				-o "Resources/Icon/AppIcon.iconset/icon_$${name}.png"; \
		done; \
		iconutil -c icns Resources/Icon/AppIcon.iconset -o Resources/Icon/AppIcon.icns; \
	fi

sign: bundle
	codesign --force --deep --sign - \
	  --entitlements $(ENTITLEMENTS) \
	  --options runtime \
	  $(APP_BUNDLE)
	@codesign -dvv $(APP_BUNDLE) 2>&1 | head -5

run: sign
	@echo "Launching $(APP_BUNDLE)..."
	@pkill -x $(APP_NAME) 2>/dev/null || true
	open $(APP_BUNDLE)

debug:
	$(SWIFT) build -c debug
	@$(MAKE) bundle CONFIG=debug
	@$(MAKE) sign CONFIG=debug
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) build
