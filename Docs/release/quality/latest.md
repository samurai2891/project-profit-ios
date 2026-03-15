# Release Quality Latest Green Evidence

REL-P0-12 の release 判定に使う curated snapshot です。`latest-lane.md` や単一 lane 実行では更新せず、対象 4 lane が fully-green で揃った run のみを保持します。

- workflow_name: Release Quality
- run_id: 22795166115
- run_number: 5
- run_url: https://github.com/samurai2891/project-profit-ios/actions/runs/22795166115
- event: pull_request
- head_branch: refactor/canonical-redesign
- head_sha: 86b7b08a52d206d5d6f0eb9903327457e7fca518
- created_at: 2026-03-07 16:58:01 JST (2026-03-07T07:58:01Z)
- completed_at: 2026-03-07 17:12:57 JST (2026-03-07T08:12:57Z)
- overall_status: ok

## simulator-health

- status: ok
- reason: Simulator health check passed
- simulator_device: iPhone 16 Pro

## golden-baseline

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 16 Pro
- test_summary: Executed 6 tests, with 0 failures
- summary_path: /tmp/release-quality/golden-baseline/summary.md
- log_path: /tmp/release-quality/golden-baseline/xcodebuild.log
- xcresult_path: /tmp/release-quality/golden-baseline/golden-baseline.xcresult
- metrics_path: /tmp/release-quality/golden-baseline/performance_metrics.txt

## canonical-e2e

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 16 Pro
- test_summary: Executed 3 tests, with 0 failures
- summary_path: /tmp/release-quality/canonical-e2e/summary.md
- log_path: /tmp/release-quality/canonical-e2e/xcodebuild.log
- xcresult_path: /tmp/release-quality/canonical-e2e/canonical-e2e.xcresult
- metrics_path: /tmp/release-quality/canonical-e2e/performance_metrics.txt

## migration-rehearsal

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 16 Pro
- test_summary: Executed 8 tests, with 0 failures
- summary_path: /tmp/release-quality/migration-rehearsal/summary.md
- log_path: /tmp/release-quality/migration-rehearsal/xcodebuild.log
- xcresult_path: /tmp/release-quality/migration-rehearsal/migration-rehearsal.xcresult
- metrics_path: /tmp/release-quality/migration-rehearsal/performance_metrics.txt

## performance-gate

- status: ok
- reason: xcodebuild test succeeded
- simulator_device: iPhone 16 Pro
- test_summary: Executed 4 tests, with 0 failures
- summary_path: /tmp/release-quality/performance-gate/summary.md
- log_path: /tmp/release-quality/performance-gate/xcodebuild.log
- xcresult_path: /tmp/release-quality/performance-gate/performance-gate.xcresult
- metrics_path: /tmp/release-quality/performance-gate/performance_metrics.txt
