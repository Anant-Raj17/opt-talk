.PHONY: build app run clean cert sign

BUILD_DIR := .build/release
APP := dist/opt-talk.app
BUNDLE_ID := com.opttalk.app
CERT_NAME := opt-talk

# Hash of a valid Apple Development / Developer ID identity. Override with
# CODESIGN_IDENTITY="..." if you want a specific cert. Ad-hoc signing (`-`)
# pins Accessibility to the binary cdhash, which changes on every rebuild.
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID Application|Mac Developer/ { print $$2; exit }')

build:
	swift build -c release --product OptTalk

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Frameworks
	mkdir -p $(APP)/Contents/Resources
	cp $(BUILD_DIR)/OptTalk $(APP)/Contents/MacOS/OptTalk
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp -R $(BUILD_DIR)/llama.framework $(APP)/Contents/Frameworks/
	-cp -R $(BUILD_DIR)/FluidAudio_FluidAudio.bundle $(APP)/Contents/Resources/
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP)/Contents/MacOS/OptTalk
	@$(MAKE) sign
	@echo "Built $(APP)"

sign:
	@identity="$(CODESIGN_IDENTITY)"; \
	if [ -z "$$identity" ]; then \
		if security find-identity -p codesigning 2>/dev/null | grep -F '"$(CERT_NAME)"' >/dev/null; then \
			identity="$(CERT_NAME)"; \
		else \
			echo >&2 "No code-signing identity found. Run: make cert"; \
			echo >&2 "Falling back to ad-hoc signing (Accessibility will reset on each rebuild)."; \
			identity="-"; \
		fi; \
	fi; \
	echo "Signing with $$identity"; \
	if [ -d "$(APP)/Contents/Frameworks/llama.framework" ]; then \
		codesign --force --sign "$$identity" --timestamp=none "$(APP)/Contents/Frameworks/llama.framework"; \
	fi; \
	codesign --force --sign "$$identity" --timestamp=none --identifier $(BUNDLE_ID) "$(APP)"; \
	codesign -d -r- "$(APP)" 2>&1 | sed -n 's/^.*designated => /designated => /p'

# Local self-signed identity for machines without Apple Development certs.
cert:
	@if security find-identity -p codesigning 2>/dev/null | grep -F '"$(CERT_NAME)"' >/dev/null; then \
		echo "Certificate \"$(CERT_NAME)\" already exists."; \
		exit 0; \
	fi
	@tmpdir=$$(mktemp -d); \
	openssl req -x509 -newkey rsa:2048 -days 3650 \
		-keyout "$$tmpdir/key.pem" -out "$$tmpdir/cert.pem" -nodes \
		-subj "/CN=$(CERT_NAME)/" \
		-addext "basicConstraints=critical,CA:false" \
		-addext "keyUsage=critical,digitalSignature" \
		-addext "extendedKeyUsage=codeSigning"; \
	if openssl pkcs12 -export -legacy \
		-in "$$tmpdir/cert.pem" -inkey "$$tmpdir/key.pem" \
		-out "$$tmpdir/cert.p12" -passout pass:opttalk \
		-name "$(CERT_NAME)" 2>/dev/null; then \
		true; \
	else \
		openssl pkcs12 -export \
			-in "$$tmpdir/cert.pem" -inkey "$$tmpdir/key.pem" \
			-out "$$tmpdir/cert.p12" -passout pass:opttalk \
			-name "$(CERT_NAME)"; \
	fi; \
	security import "$$tmpdir/cert.p12" -k ~/Library/Keychains/login.keychain-db \
		-P opttalk -T /usr/bin/codesign -T /usr/bin/security; \
	rm -rf "$$tmpdir"; \
	echo "Created code-signing certificate \"$(CERT_NAME)\" in your login keychain."

run: app
	open $(APP)

clean:
	swift package clean
	rm -rf dist .build
