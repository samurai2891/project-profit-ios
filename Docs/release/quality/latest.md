# Release Quality Latest Snapshot

2026-04-07 の current HEAD full release certification snapshot です。release gate に含まれる全 lane を current HEAD で再採取し、追加の targeted regression も warm cache で再確認した結果を保持します。

- workflow_name: Release Quality
- run_id: local
- run_number: local
- run_url: local
- event: local
- head_branch: main
- head_sha: a1f122b8b3e828231b38f9d7ec8cc467fed89be5
- created_at: 2026-04-07 14:36:00 JST (2026-04-07T14:36:00+09:00)
- completed_at: 2026-04-07 15:22:44 JST (2026-04-07T15:22:44+09:00)
- overall_status: ok

## simulator-health

- status: ok
- reason: Simulator health check passed (deterministic preference selection)
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B

## golden-baseline

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B
- test_summary: Executed 7 tests, with 0 failures
- summary_path: artifacts/release-quality/golden-baseline/summary.md
- log_path: artifacts/release-quality/golden-baseline/xcodebuild.log
- xcresult_path: artifacts/release-quality/golden-baseline/golden-baseline.xcresult
- metrics_path: artifacts/release-quality/golden-baseline/performance_metrics.txt

## release-build

- status: ok
- reason: xcodebuild build succeeded
- mode: build
- configuration: Release
- summary_path: artifacts/release-quality/release-build/summary.md
- log_path: artifacts/release-quality/release-build/xcodebuild.log

## performance-gate

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B
- test_summary: Executed 4 tests, with 0 failures
- summary_path: artifacts/release-quality/performance-gate/summary.md
- log_path: artifacts/release-quality/performance-gate/xcodebuild.log
- xcresult_path: artifacts/release-quality/performance-gate/performance-gate.xcresult
- metrics_path: artifacts/release-quality/performance-gate/performance_metrics.txt
- performance_metrics:
  - performance.export.seconds=1.3789360523223877
  - performance.migration.seconds=0.4448509216308594
  - performance.projection.seconds=0.8415590524673462
  - performance.search.seconds=0.7561639547348022

## canonical-e2e

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B
- test_summary: Executed 71 tests, with 0 failures
- summary_path: artifacts/release-quality/canonical-e2e/summary.md
- log_path: artifacts/release-quality/canonical-e2e/xcodebuild.log
- xcresult_path: artifacts/release-quality/canonical-e2e/canonical-e2e.xcresult
- metrics_path: artifacts/release-quality/canonical-e2e/performance_metrics.txt

## migration-rehearsal

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B
- test_summary: Executed 13 tests, with 0 failures
- summary_path: artifacts/release-quality/migration-rehearsal/summary.md
- log_path: artifacts/release-quality/migration-rehearsal/xcodebuild.log
- xcresult_path: artifacts/release-quality/migration-rehearsal/migration-rehearsal.xcresult
- metrics_path: artifacts/release-quality/migration-rehearsal/performance_metrics.txt

## books

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B
- test_summary: Executed 6 tests, with 0 failures
- summary_path: artifacts/release-quality/books/summary.md
- log_path: artifacts/release-quality/books/xcodebuild.log
- xcresult_path: artifacts/release-quality/books/books.xcresult
- metrics_path: artifacts/release-quality/books/performance_metrics.txt

## forms

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17
- simulator_id: F14C12AF-7F90-4311-BECD-E70E3031CE9B
- test_summary: Executed 61 tests, with 0 failures
- summary_path: artifacts/release-quality/forms/summary.md
- log_path: artifacts/release-quality/forms/xcodebuild.log
- xcresult_path: artifacts/release-quality/forms/forms.xcresult
- metrics_path: artifacts/release-quality/forms/performance_metrics.txt

## xlsx-verify

- status: ok
- reason: all xlsx verify scripts passed
- summary_path: artifacts/release-quality/xlsx-verify/summary.md
- log_path: artifacts/release-quality/xlsx-verify/xlsx-verify.log

## targeted-regression

- status: ok
- reason: fixes introduced in Wave 1 revalidated on warmed DerivedData
- test_summary: Executed 25 tests, with 0 failures
- suites:
  - LegacyDataMigrationExecutorTests
  - CanonicalRepositoriesTests
  - DocumentWorkflowUseCaseTests
