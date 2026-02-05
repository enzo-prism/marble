SHELL := /bin/bash

.PHONY: test unit ui ui-smoke audit snapshot snapshot-quick snapshot-record quick only

test:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleTests
	SCHEME=marble scripts/run_snapshot_suite.sh

unit:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleTests

ui:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests

ui-smoke:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests/SmokeNavigationUITests

audit:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests/AccessibilityAuditUITests

snapshot:
	SCHEME=marble scripts/run_snapshot_suite.sh

snapshot-quick:
	SNAPSHOT_SUITE=quick SCHEME=marble scripts/run_snapshot_suite.sh

snapshot-record:
	SNAPSHOT_TESTING_RECORD=all RECORD_SNAPSHOTS=1 SCHEME=marble scripts/run_snapshot_suite.sh -testPlan MarbleSnapshotRecord

quick: unit snapshot-quick

only:
	@if [[ -z "$(TEST)" ]]; then echo "Set TEST=Target/Class/testName"; exit 1; fi
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:$(TEST)
