.PHONY: build app run clean

BUILD_DIR := .build/release
APP := dist/opt-talk.app

build:
	swift build -c release --product OptTalk

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Frameworks
	mkdir -p $(APP)/Contents/Resources
	cp $(BUILD_DIR)/OptTalk $(APP)/Contents/MacOS/OptTalk
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp -R $(BUILD_DIR)/llama.framework $(APP)/Contents/Frameworks/
	-cp -R $(BUILD_DIR)/FluidAudio_FluidAudio.bundle $(APP)/Contents/Resources/
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP)/Contents/MacOS/OptTalk
	codesign --force --sign - --timestamp=none --deep $(APP) || true
	@echo "Built $(APP)"

run: app
	open $(APP)

clean:
	swift package clean
	rm -rf dist .build
