SHELL := /bin/bash

.PHONY: test ui audit snapshot snapshot-record only

test:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleTests
	SCHEME=marble scripts/run_snapshot_suite.sh

ui:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests

audit:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests/AccessibilityAuditUITests

snapshot:
	SCHEME=marble scripts/run_snapshot_suite.sh

snapshot-record:
	SNAPSHOT_TESTING_RECORD=all RECORD_SNAPSHOTS=1 SCHEME=marble scripts/run_snapshot_suite.sh -testPlan MarbleSnapshotRecord

only:
	@if [[ -z "$(TEST)" ]]; then echo "Set TEST=Target/Class/testName"; exit 1; fi
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:$(TEST)
