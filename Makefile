.PHONY: app run test

app:
	swift build -c release --product StayPane
	@BINARY_PATH="$$(swift build -c release --show-bin-path)/StayPane"; \
	APP_PATH="$(CURDIR)/.build/StayPane.app"; \
	rm -rf "$$APP_PATH"; \
	install -d "$$APP_PATH/Contents/MacOS"; \
	install -m 755 "$$BINARY_PATH" "$$APP_PATH/Contents/MacOS/StayPane"; \
	install -m 644 "$(CURDIR)/Resources/StayPane-Info.plist" "$$APP_PATH/Contents/Info.plist"; \
	codesign --force --sign - --timestamp=none "$$APP_PATH"; \
	echo "Built $$APP_PATH"

run: app
	open "$(CURDIR)/.build/StayPane.app"

test:
	swift test
