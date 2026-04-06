# Release Quality Evidence

`scripts/run_release_quality_lane.sh` は `RELEASE_QUALITY_EVIDENCE_DIR` が設定された場合のみ、
リポジトリで追跡しやすい Markdown の lane 実行証跡を出力します。

`latest.md` は script の出力先ではなく、release 判定用に commit される
最新 fully-green `Release Quality` run の curated snapshot です。
current HEAD が fully-green でない場合でも、最後の green snapshot を保持したままにします。

## XcodeGen 同期ガード

`release-quality` workflow は先頭で `scripts/check_xcodegen_sync.sh` を実行し、
`project.yml` と `ProjectProfit.xcodeproj` の同期崩れを fail-fast で検出します。

ローカル確認:

```bash
xcodegen generate
bash scripts/check_xcodegen_sync.sh
```

`status=error` の場合は `xcodegen generate` 後の `ProjectProfit.xcodeproj` 差分を commit してから、
release lane を再実行してください。

## Repo 管理境界

- repo 管理対象の最小セットは `latest.md`、`latest-lane.md`、`release-build.md`、`golden-baseline.md`、`canonical-e2e.md`、`migration-rehearsal.md`、`performance-gate.md`、`books.md`、`forms.md`、`xlsx-verify.md` です。
- `ProjectProfit/PrivacyInfo.xcprivacy`、`Docs/legal/privacy_policy.md`、`Docs/release/checklist.md` も release 補助ファイルとして repo 管理します。
- `support URL` は repo 内で実値を持たない外部設定であり、このディレクトリの artifact には含めません。

## 使い方

```bash
RELEASE_QUALITY_LANE=golden-baseline \
RELEASE_QUALITY_SIMULATOR_DEVICE='iPhone 17 Pro' \
RELEASE_QUALITY_ONLY_TESTING='ProjectProfitTests/GoldenBaselineTests' \
RELEASE_QUALITY_EVIDENCE_DIR='Docs/release/quality' \
scripts/run_release_quality_lane.sh
```

CI の simulator は `scripts/check_simulator_health.sh` が `RELEASE_QUALITY_SIMULATOR_PREFERENCES`
（既定: `iPhone 17 Pro,iPhone 17,iPhone 17 Pro Max,iPhone 16e,iPhone 16 Pro,iPhone 16`）をもとに決定的に選択します。

Release 構成のビルド検証だけ行う場合（シミュレータ不要）:

```bash
RELEASE_QUALITY_LANE=release-build \
RELEASE_QUALITY_MODE=build \
RELEASE_QUALITY_CONFIGURATION=Release \
RELEASE_QUALITY_DESTINATION='generic/platform=iOS' \
RELEASE_QUALITY_EVIDENCE_DIR='Docs/release/quality' \
scripts/run_release_quality_lane.sh
```

## 出力ファイル

- `latest.md`
  最新 fully-green `Release Quality` run の curated snapshot。4 lane が揃ったときだけ更新します（`release-build` は `release-build.md` で追跡）。
- `latest-lane.md`
  `scripts/run_release_quality_lane.sh` が最後に出力した単一 lane の証跡。
- `<lane>.md`
  レーン名ごとの最新証跡（例: `golden-baseline.md`）。`latest-lane.md` と同じ固定フォーマット。
  `xlsx-verify.md` は simulator 非依存の xlsx verification gate の個票です。

## 更新ルール

- lane 実行時は `RELEASE_QUALITY_EVIDENCE_DIR='Docs/release/quality'` を必須とします。
- 単発 lane 実行で commit する最小 artifact は `latest-lane.md` と対応する `<lane>.md` です。
- release 判定用として repo で維持する最小 artifact セットは `latest.md`、`latest-lane.md`、lane 別 8 本です（`release-build` と `xlsx-verify` を含む）。
- `latest.md` は fully-green 4 lane の curated snapshot なので、単発 lane 実行では更新しません。
- current HEAD の判定時に `latest.md` の `head_sha` が current HEAD と不一致なら、lane 別 md を current HEAD の正本として扱います。
- `latest-lane.md` または `<lane>.md` に placeholder 値が残る状態は release 判定不可です。

## lane 証跡の固定フォーマット

`latest-lane.md` と `<lane>.md` には、以下の項目を固定で記録します。

- `generated_at`
- `lane`
- `status`
- `reason`
- `mode`
- `configuration`
- `head_sha`
- `run_id`
- `run_url`
- `simulator_device`
- `test_summary`
- `summary_path`
- `log_path`
- `xcresult_path`
- `metrics_path`

`*_path` は、リポジトリ配下のパスであればリポジトリ相対で記録されます。
リポジトリ外のパスは絶対パスで記録されます。

`xlsx-verify` lane は simulator/xcresult/metrics を持たないため、`summary_path` と `log_path` だけを記録します。
