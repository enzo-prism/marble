SHELL := /bin/bash

SCHEME ?= marble
PROJECT ?= marble.xcodeproj
ASC_APP ?= 6757725234
ASC_BUNDLE_ID ?= Prism.marble
ASC_ARTIFACTS_DIR ?= .asc/artifacts
ASC_ARCHIVE_PATH ?= $(ASC_ARTIFACTS_DIR)/marble.xcarchive
ASC_IPA_PATH ?= $(ASC_ARTIFACTS_DIR)/marble.ipa
ASC_EXPORT_OPTIONS ?=
ASC_MARKETING_VERSION ?= $(shell ruby -e 'project = File.read("$(PROJECT)/project.pbxproj"); versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq; abort("not found") if versions.empty?; print versions.first')
ASC_APPSTORE_VERSION ?= 2.0
ASC_TESTFLIGHT_VERSION ?= $(ASC_MARKETING_VERSION)
ASC_APPSTORE_PUBLISH_VERSION ?=
ASC_PLATFORM ?= IOS
ASC_TESTFLIGHT_GROUP ?=
ASC_POLL_INTERVAL ?= 30s
ASC_UPLOAD_TIMEOUT ?= 45m
ASC_APPSTORE_SUBMIT_FLAGS ?=
ASC_TESTFLIGHT_FLAGS ?=

.PHONY: test unit ui ui-smoke audit snapshot snapshot-quick snapshot-record quick only verify-widget-plist
.PHONY: asc-auth asc-doctor asc-app asc-builds asc-version asc-status asc-review asc-validate asc-next-build
.PHONY: asc-archive asc-export asc-publish-testflight asc-publish-appstore

verify-widget-plist:
	@test -f MarbleWidgets/Info.plist || { echo "Missing MarbleWidgets/Info.plist; the widget target uses GENERATE_INFOPLIST_FILE=NO."; exit 1; }

test: verify-widget-plist
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleTests
	SCHEME=$(SCHEME) scripts/run_snapshot_suite.sh

unit: verify-widget-plist
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleTests

ui:
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleUITests -skip-testing:MarbleUITests/AccessibilityAuditUITests

ui-smoke:
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleUITests/SmokeNavigationUITests

audit:
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleUITests/AccessibilityAuditUITests

snapshot:
	SCHEME=$(SCHEME) scripts/run_snapshot_suite.sh

snapshot-quick:
	SNAPSHOT_SUITE=quick SCHEME=$(SCHEME) scripts/run_snapshot_suite.sh

snapshot-record:
	SNAPSHOT_TESTING_RECORD=all RECORD_SNAPSHOTS=1 SCHEME=$(SCHEME) scripts/run_snapshot_suite.sh -testPlan MarbleSnapshotRecord

quick: unit snapshot-quick

only:
	@if [[ -z "$(TEST)" ]]; then echo "Set TEST=Target/Class/testName"; exit 1; fi
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:$(TEST)

asc-auth:
	asc auth status --validate --output json --pretty

asc-doctor:
	asc auth doctor --output json --pretty

asc-app:
	asc apps list --bundle-id "$(ASC_BUNDLE_ID)" --output json --pretty | jq '.data[] | select(.id == "$(ASC_APP)" or .attributes.bundleId == "$(ASC_BUNDLE_ID)") | {id, name: .attributes.name, bundleId: .attributes.bundleId, sku: .attributes.sku, primaryLocale: .attributes.primaryLocale}'

asc-builds:
	asc builds list --app "$(ASC_APP)" --sort -uploadedDate --limit 10 --output table

asc-version:
	asc xcode version view --project "$(PROJECT)" --target "$(SCHEME)" --output json --pretty
	@printf 'marketingVersionFallback='
	@ruby -e 'project = File.read("$(PROJECT)/project.pbxproj"); versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq; abort("not found") if versions.empty?; puts versions.join(",")'

asc-status:
	asc status --app "$(ASC_APP)" --output table

asc-review:
	asc review status --app "$(ASC_APP)" --version "$(ASC_APPSTORE_VERSION)" --platform "$(ASC_PLATFORM)" --output table
	asc review doctor --app "$(ASC_APP)" --version "$(ASC_APPSTORE_VERSION)" --platform "$(ASC_PLATFORM)" --output table

asc-validate:
	asc validate --app "$(ASC_APP)" --version "$(ASC_APPSTORE_VERSION)" --platform "$(ASC_PLATFORM)" --output table

asc-next-build:
	asc builds next-build-number --app "$(ASC_APP)" --version "$(ASC_TESTFLIGHT_VERSION)" --platform "$(ASC_PLATFORM)" --output table

asc-archive:
	mkdir -p "$(ASC_ARTIFACTS_DIR)"
	asc xcode archive --project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Release --archive-path "$(ASC_ARCHIVE_PATH)" --overwrite --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS --output json --pretty

asc-export:
	@if [[ -z "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Set ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist"; exit 1; fi
	@if [[ ! -f "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Export options file not found: $(ASC_EXPORT_OPTIONS)"; exit 1; fi
	mkdir -p "$(ASC_ARTIFACTS_DIR)"
	asc xcode export --archive-path "$(ASC_ARCHIVE_PATH)" --export-options "$(ASC_EXPORT_OPTIONS)" --ipa-path "$(ASC_IPA_PATH)" --overwrite --output json --pretty

asc-publish-testflight:
	@if [[ -z "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Set ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist"; exit 1; fi
	@if [[ ! -f "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Export options file not found: $(ASC_EXPORT_OPTIONS)"; exit 1; fi
	@if [[ -z "$(ASC_TESTFLIGHT_GROUP)" ]]; then echo "Set ASC_TESTFLIGHT_GROUP='Group name or ID'"; exit 1; fi
	mkdir -p "$(ASC_ARTIFACTS_DIR)"
	rm -rf "$(ASC_ARCHIVE_PATH)" "$(ASC_IPA_PATH)"
	asc publish testflight --app "$(ASC_APP)" --project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Release --archive-path "$(ASC_ARCHIVE_PATH)" --export-options "$(ASC_EXPORT_OPTIONS)" --ipa-path "$(ASC_IPA_PATH)" --archive-xcodebuild-flag=-destination --archive-xcodebuild-flag=generic/platform=iOS --version "$(ASC_TESTFLIGHT_VERSION)" --group "$(ASC_TESTFLIGHT_GROUP)" --wait --poll-interval "$(ASC_POLL_INTERVAL)" --timeout "$(ASC_UPLOAD_TIMEOUT)" --output json --pretty $(ASC_TESTFLIGHT_FLAGS)

asc-publish-appstore:
	@if [[ -z "$(ASC_APPSTORE_PUBLISH_VERSION)" ]]; then echo "Set ASC_APPSTORE_PUBLISH_VERSION explicitly before publishing to the App Store"; exit 1; fi
	@if [[ -z "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Set ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist"; exit 1; fi
	@if [[ ! -f "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Export options file not found: $(ASC_EXPORT_OPTIONS)"; exit 1; fi
	mkdir -p "$(ASC_ARTIFACTS_DIR)"
	rm -rf "$(ASC_ARCHIVE_PATH)" "$(ASC_IPA_PATH)"
	asc publish appstore --app "$(ASC_APP)" --project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Release --archive-path "$(ASC_ARCHIVE_PATH)" --export-options "$(ASC_EXPORT_OPTIONS)" --ipa-path "$(ASC_IPA_PATH)" --archive-xcodebuild-flag=-destination --archive-xcodebuild-flag=generic/platform=iOS --version "$(ASC_APPSTORE_PUBLISH_VERSION)" --wait --poll-interval "$(ASC_POLL_INTERVAL)" --timeout "$(ASC_UPLOAD_TIMEOUT)" --output json --pretty $(ASC_APPSTORE_SUBMIT_FLAGS)
