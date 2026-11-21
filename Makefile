PACKAGES := SurgeCore SurgeIngestTailer SurgeIngestProxy SurgeWallets SurgeUI SurgeStateStore
FORMAT_PATHS := App/SurgeMenuBarApp Widget/SurgeWidget Widget/SurgeWidgetTests Packages/*/Sources Packages/*/Tests Packages/*/Package.swift
APP := build/Build/Products/Debug/Surge.app

.PHONY: project build run stop test lint format

project:
	xcodegen generate

build: project
	xcodebuild -project Surge.xcodeproj -scheme Surge -destination 'platform=macOS' \
		-derivedDataPath build build

run: build stop
	open $(APP)

stop:
	-pkill -x Surge

test:
	@for p in $(PACKAGES); do echo "== $$p"; swift test --package-path Packages/$$p || exit 1; done

lint:
	swiftlint lint --strict
	swift-format lint --strict --recursive $(FORMAT_PATHS)

format:
	swift-format format --in-place --recursive $(FORMAT_PATHS)
