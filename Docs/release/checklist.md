# Release Checklist

最終更新日: 2026年3月14日

このファイルは、ProjectProfit の release 判定を行うための repo 管理チェックリストです。
手順の説明ではなく、何を確認し、どの証跡を見れば release 可否を判定できるかの正本として扱います。

## 判定原則

- `Release Quality` workflow の現行ジョブ構成を正本とする。
- `golden-baseline` 以降の lane は `RELEASE_QUALITY_EVIDENCE_DIR` を設定して実行し、Markdown 証跡を残す。
- lane の判定は `status`、`reason`、`simulator_device`、`test_summary`、artifact path で行う。
- `Docs/release/quality/latest.md` は latest fully-green curated snapshot として保持し、current HEAD 判定のたびに必ずしも更新しない。
- current HEAD の release 可否は、まず `Docs/release/quality/latest.md` の `head_sha` が current HEAD と一致するかで判定経路を分ける。
- `latest.md` の `head_sha` が current HEAD と不一致の場合は、`Docs/release/quality/<lane>.md` を current HEAD の正本として扱い、lane 個票の `ok/error` 実測で release 可否を判定する。
- `latest.md` と lane 個票が矛盾する場合は、current HEAD に対応する lane 個票を優先する。
- `support URL` はこの checklist の対象外とする。repo 内で実値を確定できないため。

## Repo 管理境界

- repo 管理対象の最小セットは `ProjectProfit/PrivacyInfo.xcprivacy`、`Docs/legal/privacy_policy.md`、`Docs/release/checklist.md`、`Docs/release/quality/latest.md`、`Docs/release/quality/latest-lane.md`、`Docs/release/quality/golden-baseline.md`、`Docs/release/quality/canonical-e2e.md`、`Docs/release/quality/migration-rehearsal.md`、`Docs/release/quality/performance-gate.md`、`Docs/release/quality/books.md`、`Docs/release/quality/forms.md` とする。
- `Docs/release/quality/latest.md` は REL-P0-12 対象 4 lane の latest fully-green snapshot を保持する curated artifact とする。
- `Docs/release/quality/latest-lane.md` は最後に実行した単一 lane の証跡とする。
- `Docs/release/quality/<lane>.md` は lane ごとの最新証跡とする。
- `support URL` は release 判定用の repo artifact ではなく、repo 外設定として管理する。

## 根拠ファイル

- `.github/workflows/release-quality.yml`
- `scripts/check_simulator_health.sh`
- `scripts/run_release_quality_lane.sh`
- `Docs/release/quality/latest.md`
- `Docs/release/quality/latest-lane.md`

## Current HEAD 判定手順

1. `git rev-parse HEAD` で判定対象の HEAD を確認する。
2. `Docs/release/quality/latest.md` の `head_sha` が current HEAD と一致する場合は、curated 4 lane は `latest.md` を release gate の正本として扱う。
3. `latest.md` の `head_sha` が current HEAD と不一致の場合は、curated 4 lane も含めて `Docs/release/quality/<lane>.md` を current HEAD の正本として扱う。
4. `Docs/release/quality/latest-lane.md` は最後に実行した単一 lane の確認用であり、release gate の合否判定は lane 個票を優先する。
5. current HEAD の lane 個票が `status: error` の場合、その lane は release 不可と判定する。`latest.md` に古い green が残っていても上書き解釈しない。

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
  - `Docs/release/quality/latest.md` または `Docs/release/quality/golden-baseline.md`
- 確認項目:
  - `latest.md` の `head_sha` が current HEAD と一致するか、または `Docs/release/quality/golden-baseline.md` が current HEAD の個票として更新されている
  - 判定に使う証跡の `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている
  - `Docs/release/quality/golden-baseline.md` が current HEAD で `status: error` の場合は release 不可

### 3. Canonical E2E

- lane: `canonical-e2e`
- 証跡:
  - `Docs/release/quality/latest.md` または `Docs/release/quality/canonical-e2e.md`
- 確認項目:
  - `latest.md` の `head_sha` が current HEAD と一致するか、または `Docs/release/quality/canonical-e2e.md` が current HEAD の個票として更新されている
  - 判定に使う証跡の `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている
  - `Docs/release/quality/canonical-e2e.md` が current HEAD で `status: error` の場合は release 不可

### 4. Migration Rehearsal

- lane: `migration-rehearsal`
- 証跡:
  - `Docs/release/quality/latest.md` または `Docs/release/quality/migration-rehearsal.md`
- 確認項目:
  - `latest.md` の `head_sha` が current HEAD と一致するか、または `Docs/release/quality/migration-rehearsal.md` が current HEAD の個票として更新されている
  - 判定に使う証跡の `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている
  - `Docs/release/quality/migration-rehearsal.md` が current HEAD で `status: error` の場合は release 不可

### 5. Performance Gate

- lane: `performance-gate`
- 証跡:
  - `Docs/release/quality/latest.md` または `Docs/release/quality/performance-gate.md`
- 確認項目:
  - `latest.md` の `head_sha` が current HEAD と一致するか、または `Docs/release/quality/performance-gate.md` が current HEAD の個票として更新されている
  - 判定に使う証跡の `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている
  - `Docs/release/quality/performance-gate.md` が current HEAD で `status: error` の場合は release 不可

### 6. Books

- lane: `books`
- 証跡:
  - `Docs/release/quality/books.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

### 7. Forms

- lane: `forms`
- 証跡:
  - `Docs/release/quality/forms.md`
- 確認項目:
  - `status: ok`
  - `reason` が成功理由で埋まっている
  - `simulator_device` が記録されている
  - `test_summary` が記録されている
  - `summary_path` / `log_path` / `xcresult_path` / `metrics_path` が記録されている

## 実行時の固定条件

- lane 実行時は `RELEASE_QUALITY_EVIDENCE_DIR='Docs/release/quality'` を設定する。
- commit 管理する最小 artifact は `latest.md`、`latest-lane.md`、lane 別 6 本とする。
- `latest-lane.md` または lane 別 md に placeholder 値が残る場合は release 不可とする。
- `Docs/release/quality/latest.md` は REL-P0-12 対象 gate の最新 fully-green snapshot として commit 管理する。
- `Docs/release/quality/latest-lane.md` は最後に実行した lane の証跡として上書きされる。
- lane ごとの判定は `Docs/release/quality/<lane>.md` を優先し、単一 lane の直近実行確認には `Docs/release/quality/latest-lane.md` を使う。
- release gate 全体の最新 green 確認には `Docs/release/quality/latest.md` を使う。
- ただし current HEAD 判定では、`latest.md` の `head_sha` が current HEAD と不一致なら lane 個票を優先する。

## 2026-03-14 Current State

- current HEAD: `8b525b6811f90a99610eb4b713972478ee60fbc1`
- `Docs/release/quality/latest.md` は 2026-03-07 / `86b7b08a52d206d5d6f0eb9903327457e7fca518` の fully-green snapshot のまま
- current HEAD の lane 個票実測:
  - `golden-baseline`: `status: error`
  - `canonical-e2e`: `status: error`
  - `migration-rehearsal`: `status: error`
  - `performance-gate`: `status: error`
  - `forms`: `status: ok`
  - `books`: `status: ok`
- current HEAD の failure 根拠は lane 個票の `log_path` / `xcresult_path` を参照する
