# Release Quality Evidence

`scripts/run_release_quality_lane.sh` は `RELEASE_QUALITY_EVIDENCE_DIR` が設定された場合のみ、
リポジトリで追跡しやすい Markdown の lane 実行証跡を出力します。

`latest.md` は script の出力先ではなく、release 判定用に commit される
最新 fully-green `Release Quality` run の curated snapshot です。
current HEAD が fully-green でない場合でも、最後の green snapshot を保持したままにします。

## Repo 管理境界

- repo 管理対象の最小セットは `latest.md`、`latest-lane.md`、`golden-baseline.md`、`canonical-e2e.md`、`migration-rehearsal.md`、`performance-gate.md`、`books.md`、`forms.md` です。
- `ProjectProfit/PrivacyInfo.xcprivacy`、`Docs/privacy_policy.md`、`Docs/release_checklist.md` も release 補助ファイルとして repo 管理します。
- `support URL` は repo 内で実値を持たない外部設定であり、このディレクトリの artifact には含めません。

## 使い方

```bash
RELEASE_QUALITY_LANE=golden-baseline \
RELEASE_QUALITY_SIMULATOR_DEVICE='iPhone 16' \
RELEASE_QUALITY_ONLY_TESTING='ProjectProfitTests/GoldenBaselineTests' \
RELEASE_QUALITY_EVIDENCE_DIR='Docs/release_quality' \
scripts/run_release_quality_lane.sh
```

## 出力ファイル

- `latest.md`
  最新 fully-green `Release Quality` run の curated snapshot。4 lane が揃ったときだけ更新します。
- `latest-lane.md`
  `scripts/run_release_quality_lane.sh` が最後に出力した単一 lane の証跡。
- `<lane>.md`
  レーン名ごとの最新証跡（例: `golden-baseline.md`）。`latest-lane.md` と同じ固定フォーマット。

## 更新ルール

- lane 実行時は `RELEASE_QUALITY_EVIDENCE_DIR='Docs/release_quality'` を必須とします。
- 単発 lane 実行で commit する最小 artifact は `latest-lane.md` と対応する `<lane>.md` です。
- release 判定用として repo で維持する最小 artifact セットは `latest.md`、`latest-lane.md`、lane 別 6 本です。
- `latest.md` は fully-green 4 lane の curated snapshot なので、単発 lane 実行では更新しません。
- current HEAD の判定時に `latest.md` の `head_sha` が current HEAD と不一致なら、lane 別 md を current HEAD の正本として扱います。
- `latest-lane.md` または `<lane>.md` に placeholder 値が残る状態は release 判定不可です。

## lane 証跡の固定フォーマット

`latest-lane.md` と `<lane>.md` には、以下の項目を固定で記録します。

- `generated_at`
- `lane`
- `status`
- `reason`
- `simulator_device`
- `test_summary`
- `summary_path`
- `log_path`
- `xcresult_path`
- `metrics_path`

`*_path` は、リポジトリ配下のパスであればリポジトリ相対で記録されます。
リポジトリ外のパスは絶対パスで記録されます。
