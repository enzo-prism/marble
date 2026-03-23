SHELL := /bin/bash

SCHEME ?= marble
PROJECT ?= marble.xcodeproj
ASC_APP ?= 6757725234
ASC_BUNDLE_ID ?= Prism.marble
ASC_ARTIFACTS_DIR ?= .asc/artifacts
ASC_ARCHIVE_PATH ?= $(ASC_ARTIFACTS_DIR)/marble.xcarchive
ASC_IPA_PATH ?= $(ASC_ARTIFACTS_DIR)/marble.ipa
ASC_EXPORT_OPTIONS ?=

.PHONY: test unit ui ui-smoke audit snapshot snapshot-quick snapshot-record quick only
.PHONY: asc-auth asc-doctor asc-app asc-builds asc-version asc-archive asc-export

test:
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleTests
	SCHEME=$(SCHEME) scripts/run_snapshot_suite.sh

unit:
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleTests

ui:
	SCHEME=$(SCHEME) scripts/xcodebuild_test.sh -only-testing:MarbleUITests

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
	asc auth status --output json --pretty

asc-doctor:
	asc doctor --output json --pretty

asc-app:
	asc apps --output json --pretty | jq '.data[] | select(.id == "$(ASC_APP)" or .attributes.bundleId == "$(ASC_BUNDLE_ID)") | {id, name: .attributes.name, bundleId: .attributes.bundleId, sku: .attributes.sku, primaryLocale: .attributes.primaryLocale}'

asc-builds:
	asc builds list --app "$(ASC_APP)" --sort -uploadedDate --limit 10 --output table

asc-version:
	asc xcode version view --project "$(PROJECT)" --target "$(SCHEME)" --output json --pretty
	@printf 'marketingVersionFallback='
	@ruby -e 'project = File.read("$(PROJECT)/project.pbxproj"); versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq; abort("not found") if versions.empty?; puts versions.join(",")'

asc-archive:
	mkdir -p "$(ASC_ARTIFACTS_DIR)"
	asc xcode archive --project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Release --archive-path "$(ASC_ARCHIVE_PATH)" --overwrite --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS --output json --pretty

asc-export:
	@if [[ -z "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Set ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist"; exit 1; fi
	@if [[ ! -f "$(ASC_EXPORT_OPTIONS)" ]]; then echo "Export options file not found: $(ASC_EXPORT_OPTIONS)"; exit 1; fi
	mkdir -p "$(ASC_ARTIFACTS_DIR)"
	asc xcode export --archive-path "$(ASC_ARCHIVE_PATH)" --export-options "$(ASC_EXPORT_OPTIONS)" --ipa-path "$(ASC_IPA_PATH)" --overwrite --output json --pretty
