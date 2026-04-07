# Release Quality Latest Snapshot

REL-P0-12 の release 判定に使う curated snapshot です。current HEAD の curated 4 lane を同一 refresh で採取した結果を保持し、green でない場合も実測をそのまま残します。

- workflow_name: Release Quality
- run_id: local
- run_number: local
- run_url: local
- event: local
- head_branch: main
- head_sha: c6a354027311474e0673806a62d44dcda9ebd55c
- created_at: 2026-04-07 12:19:25 JST (2026-04-07T12:19:25+09:00)
- completed_at: 2026-04-07 12:34:58 JST (2026-04-07T12:34:58+09:00)
- overall_status: error

## simulator-health

- status: ok
- reason: Simulator health check passed (deterministic preference selection)
- simulator_device: iPhone 17 Pro
- simulator_id: 75FD4EB2-79BE-4F1F-9225-99D392A087FC

## golden-baseline

- status: error
- reason: xcodebuild test failed
- simulator_device: iPhone 17 Pro
- simulator_id: 75FD4EB2-79BE-4F1F-9225-99D392A087FC
- test_summary: Executed 7 tests, with 4 failures
- summary_path: artifacts/release-quality/golden-baseline/summary.md
- log_path: artifacts/release-quality/golden-baseline/xcodebuild.log
- xcresult_path: artifacts/release-quality/golden-baseline/golden-baseline.xcresult
- metrics_path: artifacts/release-quality/golden-baseline/performance_metrics.txt

## canonical-e2e

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17 Pro
- simulator_id: 75FD4EB2-79BE-4F1F-9225-99D392A087FC
- test_summary: Executed 71 tests, with 0 failures
- summary_path: artifacts/release-quality/canonical-e2e/summary.md
- log_path: artifacts/release-quality/canonical-e2e/xcodebuild.log
- xcresult_path: artifacts/release-quality/canonical-e2e/canonical-e2e.xcresult
- metrics_path: artifacts/release-quality/canonical-e2e/performance_metrics.txt

## migration-rehearsal

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17 Pro
- simulator_id: 75FD4EB2-79BE-4F1F-9225-99D392A087FC
- test_summary: Executed 13 tests, with 0 failures
- summary_path: artifacts/release-quality/migration-rehearsal/summary.md
- log_path: artifacts/release-quality/migration-rehearsal/xcodebuild.log
- xcresult_path: artifacts/release-quality/migration-rehearsal/migration-rehearsal.xcresult
- metrics_path: artifacts/release-quality/migration-rehearsal/performance_metrics.txt

## performance-gate

- status: error
- reason: xcodebuild test failed
- simulator_device: iPhone 17 Pro
- simulator_id: 75FD4EB2-79BE-4F1F-9225-99D392A087FC
- test_summary: Executed 4 tests, with 1 failure
- summary_path: artifacts/release-quality/performance-gate/summary.md
- log_path: artifacts/release-quality/performance-gate/xcodebuild.log
- xcresult_path: artifacts/release-quality/performance-gate/performance-gate.xcresult
- metrics_path: artifacts/release-quality/performance-gate/performance_metrics.txt
