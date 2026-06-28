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

clean:
	swift package clean
	rm -rf $(BUNDLE)
