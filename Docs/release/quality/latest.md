# Release Quality Latest Green Evidence

REL-P0-12 の release 判定に使う curated snapshot です。`latest-lane.md` や単一 lane 実行では更新せず、対象 4 lane が fully-green で揃った run のみを保持します。

- workflow_name: Release Quality
- run_id: local
- run_number: local
- run_url: local
- event: local
- head_branch: codex/fix-release-tasks-batch-1
- head_sha: a2d059d9b9d71ac22148f7b641a83ab03249134d
- created_at: 2026-03-24 20:28:05 JST (2026-03-24T20:28:05+09:00)
- completed_at: 2026-03-24 20:36:58 JST (2026-03-24T20:36:58+09:00)
- overall_status: ok

## simulator-health

- status: ok
- reason: Simulator health check passed (deterministic preference selection)
- simulator_device: iPhone 17 Pro

## golden-baseline

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17 Pro
- test_summary: Executed 6 tests, with 0 failures
- summary_path: artifacts/release-quality/golden-baseline/summary.md
- log_path: artifacts/release-quality/golden-baseline/xcodebuild.log
- xcresult_path: artifacts/release-quality/golden-baseline/golden-baseline.xcresult
- metrics_path: artifacts/release-quality/golden-baseline/performance_metrics.txt

## canonical-e2e

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17 Pro
- test_summary: Executed 71 tests, with 0 failures
- summary_path: artifacts/release-quality/canonical-e2e/summary.md
- log_path: artifacts/release-quality/canonical-e2e/xcodebuild.log
- xcresult_path: artifacts/release-quality/canonical-e2e/canonical-e2e.xcresult
- metrics_path: artifacts/release-quality/canonical-e2e/performance_metrics.txt

## migration-rehearsal

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17 Pro
- test_summary: Executed 13 tests, with 0 failures
- summary_path: artifacts/release-quality/migration-rehearsal/summary.md
- log_path: artifacts/release-quality/migration-rehearsal/xcodebuild.log
- xcresult_path: artifacts/release-quality/migration-rehearsal/migration-rehearsal.xcresult
- metrics_path: artifacts/release-quality/migration-rehearsal/performance_metrics.txt

## performance-gate

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 17 Pro
- test_summary: Executed 4 tests, with 0 failures
- summary_path: artifacts/release-quality/performance-gate/summary.md
- log_path: artifacts/release-quality/performance-gate/xcodebuild.log
- xcresult_path: artifacts/release-quality/performance-gate/performance-gate.xcresult
- metrics_path: artifacts/release-quality/performance-gate/performance_metrics.txt
