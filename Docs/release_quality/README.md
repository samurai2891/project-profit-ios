# Release Quality Evidence

`scripts/run_release_quality_lane.sh` は `RELEASE_QUALITY_EVIDENCE_DIR` が設定された場合のみ、
リポジトリで追跡しやすい Markdown の lane 実行証跡を出力します。

`latest.md` は script の出力先ではなく、release 判定用に commit される
最新 fully-green `Release Quality` run の curated snapshot です。

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
  最新 fully-green `Release Quality` run の curated snapshot。
- `latest-lane.md`
  `scripts/run_release_quality_lane.sh` が最後に出力した単一 lane の証跡。
- `<lane>.md`
  レーン名ごとの最新証跡（例: `golden-baseline.md`）。`latest-lane.md` と同じ固定フォーマット。

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
