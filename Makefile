SHELL := /bin/bash

.PHONY: test ui audit snapshot snapshot-record only

test:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleTests -only-testing:MarbleSnapshotTests

ui:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests

audit:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleUITests/AccessibilityAuditUITests

snapshot:
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:MarbleSnapshotTests

snapshot-record:
	SNAPSHOT_TESTING_RECORD=all RECORD_SNAPSHOTS=1 SCHEME=marble scripts/xcodebuild_test.sh -testPlan MarbleSnapshotRecord -only-testing:MarbleSnapshotTests

only:
	@if [[ -z "$(TEST)" ]]; then echo "Set TEST=Target/Class/testName"; exit 1; fi
	SCHEME=marble scripts/xcodebuild_test.sh -only-testing:$(TEST)
