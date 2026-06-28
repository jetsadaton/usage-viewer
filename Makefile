APP = UsageViewer
BUNDLE = $(APP).app
BINARY = .build/release/$(APP)

.PHONY: all build run install clean open

all: build

build:
	swift build -c release

# Quick dev run (no .app bundle, but functional for testing)
run:
	swift run

# Build proper .app bundle and open it
install: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Info.plist $(BUNDLE)/Contents/
	@codesign --force --deep --sign - $(BUNDLE) 2>/dev/null || true
	@echo "✓ Built $(BUNDLE)"

open: install
	open $(BUNDLE)

dmg: install
	@rm -rf /tmp/$(APP)-dmg $(APP).dmg
	@mkdir -p /tmp/$(APP)-dmg
	@cp -r $(BUNDLE) /tmp/$(APP)-dmg/
	@ln -s /Applications /tmp/$(APP)-dmg/Applications
	@hdiutil create -volname "$(APP)" -srcfolder /tmp/$(APP)-dmg \
		-ov -format UDZO -quiet $(APP).dmg
	@rm -rf /tmp/$(APP)-dmg
	@echo "✓ Created $(APP).dmg"

clean:
	swift package clean
	rm -rf $(BUNDLE) $(APP).dmg
