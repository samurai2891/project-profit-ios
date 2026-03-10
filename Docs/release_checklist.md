# Release Checklist

最終更新日: 2026年3月10日

このファイルは、ProjectProfit の release 判定を行うための repo 管理チェックリストです。
手順の説明ではなく、何を確認し、どの証跡を見れば release 可否を判定できるかの正本として扱います。

## 判定原則

- `Release Quality` workflow の現行ジョブ構成を正本とする。
- `golden-baseline` 以降の lane は `RELEASE_QUALITY_EVIDENCE_DIR` を設定して実行し、Markdown 証跡を残す。
- lane の判定は `status`、`reason`、`simulator_device`、`test_summary`、artifact path で行う。
- `support URL` はこの checklist の対象外とする。repo 内で実値を確定できないため。

## 根拠ファイル

- `.github/workflows/release-quality.yml`
- `scripts/check_simulator_health.sh`
- `scripts/run_release_quality_lane.sh`
- `Docs/release_quality/latest.md`

## Checklist

### 1. Simulator Health

- job: `simulator-health`
- 確認元:
  - `.github/workflows/release-quality.yml`
  - `scripts/check_simulator_health.sh`
  - GitHub Actions の `simulator-health` step summary
- 確認項目:
  - `status` が `ok` または `warn`
  - `reason` が出力されている
  - `simulator_device` が出力されている
- 判定:
  - `status=error` は release 不可

### 2. Golden Baseline

- lane: `golden-baseline`
- 証跡:
  - `Docs/release_quality/golden-baseline.md`
  - `Docs/release_quality/latest.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

### 3. Canonical E2E

- lane: `canonical-e2e`
- 証跡:
  - `Docs/release_quality/canonical-e2e.md`
  - `Docs/release_quality/latest.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

### 4. Migration Rehearsal

- lane: `migration-rehearsal`
- 証跡:
  - `Docs/release_quality/migration-rehearsal.md`
  - `Docs/release_quality/latest.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

### 5. Performance Gate

- lane: `performance-gate`
- 証跡:
  - `Docs/release_quality/performance-gate.md`
  - `Docs/release_quality/latest.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

### 6. Books

- lane: `books`
- 証跡:
  - `Docs/release_quality/books.md`
  - `Docs/release_quality/latest.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

### 7. Forms

- lane: `forms`
- 証跡:
  - `Docs/release_quality/forms.md`
  - `Docs/release_quality/latest.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

## 実行時の固定条件

- lane 実行時は `RELEASE_QUALITY_EVIDENCE_DIR='Docs/release_quality'` を設定する。
- `Docs/release_quality/latest.md` は最後に実行した lane の証跡として上書きされる。
- lane ごとの判定は `Docs/release_quality/<lane>.md` を優先し、直近実行確認には `Docs/release_quality/latest.md` を使う。
