# Claude Code 実行手順

## 事前準備

```bash
# 1. 既存アプリのプロジェクトルートに Docs/ を作成
cd /path/to/ProjectProfit
mkdir -p Docs/csv_templates

# 2. 納品ファイルを配置
cp CLAUDE_CODE_INSTRUCTIONS.md Docs/
cp SPEC.md Docs/
cp master_schema.json Docs/
cp LedgerModels.swift Docs/
cp LedgerExportService.swift Docs/
cp LedgerExcelExportService.swift Docs/
cp csv_templates/* Docs/csv_templates/

# 3. Claude Code 起動
claude
```

## 初回プロンプト（コピペ用）

```
Docs/CLAUDE_CODE_INSTRUCTIONS.md を読め。
指示書に従い、段階A（調査）から開始せよ。
コードは一切書くな。既存アプリと納品ファイルの調査・精査のみを実施し、
指示書の報告フォーマットに従って結果を報告せよ。
私の承認なしに段階Bに進むことを禁止する。
```

## 段階A承認後のプロンプト

```
段階Aの調査報告を承認する。[※修正指示があればここに追記]
段階B（設計）に進め。
Docs/CLAUDE_CODE_INSTRUCTIONS.md の段階Bに従い、
統合設計を策定して報告せよ。
私の承認なしに段階Cに進むことを禁止する。
```

## 段階B承認後のプロンプト

```
段階Bの設計報告を承認する。[※修正指示があればここに追記]
段階C（実装）に進め。
Phase 1（基盤・ビルド通過）から開始せよ。
ビルドが通ったら結果を報告し、次のPhaseに進む前に私の確認を待て。
```

## Phase別の進行プロンプト

```
Phase X の結果を確認した。[※修正指示があればここに追記]
Phase X+1 に進め。
```

## バグ修正プロンプト

```
以下のバグを修正せよ:
[バグの内容]

LedgerModels.swift / LedgerExportService.swift / LedgerExcelExportService.swift は
変更不可。問題がこれらにある場合は修正案を提示し私の承認を待て。
```
