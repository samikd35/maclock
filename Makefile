.PHONY: app audit-release extension icon install run setup-chrome setup-chrome-dev test test-extension test-install test-release verify

app: extension icon
	swift build -c release --product StayPane
	swift build -c release --product StayPaneBridge
	@BINARY_PATH="$$(swift build -c release --show-bin-path)/StayPane"; \
	BRIDGE_PATH="$$(swift build -c release --show-bin-path)/StayPaneBridge"; \
	ICON_PATH="$(CURDIR)/.build/app-icon/StayPane.icns"; \
	APP_PATH="$(CURDIR)/.build/StayPane.app"; \
	rm -rf "$$APP_PATH"; \
	install -d "$$APP_PATH/Contents/MacOS"; \
	install -d "$$APP_PATH/Contents/Resources/ChromeExtension"; \
	install -m 755 "$$BINARY_PATH" "$$APP_PATH/Contents/MacOS/StayPane"; \
	install -m 755 "$$BRIDGE_PATH" "$$APP_PATH/Contents/MacOS/StayPaneBridge"; \
	cp -R "$(CURDIR)/ChromeExtension/dist/." "$$APP_PATH/Contents/Resources/ChromeExtension/"; \
	install -m 644 "$$ICON_PATH" "$$APP_PATH/Contents/Resources/StayPane.icns"; \
	install -m 644 "$(CURDIR)/Resources/StayPane-Info.plist" "$$APP_PATH/Contents/Info.plist"; \
	codesign --force --sign - --timestamp=none "$$APP_PATH"; \
	echo "Built $$APP_PATH"

extension:
	npm --prefix "$(CURDIR)/ChromeExtension" ci
	npm --prefix "$(CURDIR)/ChromeExtension" run build

icon:
	bash "$(CURDIR)/scripts/build-app-icon.sh"

install:
	bash "$(CURDIR)/scripts/install-user-app.sh"

setup-chrome:
	@echo "Repairing Chrome registration for $(HOME)/Applications/StayPane.app"
	@test -x "$(HOME)/Applications/StayPane.app/Contents/MacOS/StayPaneBridge"
	@"$(HOME)/Applications/StayPane.app/Contents/MacOS/StayPaneBridge" --register

setup-chrome-dev: app
	"$(CURDIR)/.build/StayPane.app/Contents/MacOS/StayPaneBridge" --register

run: app
	open "$(CURDIR)/.build/StayPane.app"

test:
	swift test

test-extension:
	npm --prefix "$(CURDIR)/ChromeExtension" ci
	npm --prefix "$(CURDIR)/ChromeExtension" test

test-install: app
	bash "$(CURDIR)/Tests/ReleaseTests/local-install.test.sh"

test-release:
	bash "$(CURDIR)/Tests/ReleaseTests/release-contract.test.sh"

audit-release:
	bash "$(CURDIR)/scripts/audit-source-release.sh"

verify:
	bash "$(CURDIR)/scripts/verify-source-release.sh"
