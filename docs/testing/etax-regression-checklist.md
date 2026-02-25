# e-Tax Regression Checklist

最終更新: 2026-02-26

## タグ抽出
- [ ] `etax_extract_tags.py` が fixture から `TagDictionary` を生成できる
- [ ] `internalKey` の重複/競合で失敗する
- [ ] `xmlTag` 重複で失敗する
- [ ] `required internalKey` 欠落で失敗する（`--allow-partial` なし）

## タグ適用
- [ ] `etax_apply_tags.py` が base `TaxYear` に `xmlTag/dataType` を反映できる
- [ ] `--allow-missing` なしで未反映キーがある場合は失敗する
- [ ] 反映後 `xmlTag` が空のフィールドが残らない

## ガード動作
- [ ] 未対応年分でプレビュー生成が失敗し、`unsupportedTaxYear` を返す
- [ ] 未対応年分で `.xtx/.csv` エクスポートが失敗する
- [ ] 対応年分で `internalKey -> xmlTag` 出力を確認できる

## 文字種検証
- [ ] ラベルではなく実際の出力値を検証している
- [ ] 禁止文字（例: emoji）で出力前に失敗する

## 会計年度連動
- [ ] 開始月変更でレポート期間とe-Taxプレビュー期間が一致する
- [ ] 消費税集計が `startMonth` 境界を正しく判定する

## 完了証跡
- [ ] 実行コマンド・結果ログをPRに添付
- [ ] 監査Todoに完了IDと残リスクを追記
