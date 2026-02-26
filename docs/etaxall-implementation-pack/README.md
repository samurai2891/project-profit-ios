# e-taxall implementation pack

このフォルダは、次工程の実装で参照する監査成果物・Todo・仕様書を1箇所に集約したパッケージです。
元ファイルは変更せず、コピーのみで構成しています。

## 3-Agent運用（事実ベース）
- Agent 1 (Plan): 集約対象を固定（todo / reports / evidence / meta / specs）
- Agent 2 (Research): 実在パスと件数を確認し、source-map.tsvに記録
- Agent 3 (Synthesis): フォルダ集約、manifest.csv生成、integrity-check.txtで整合性確認

## 読み順（推奨）
1. `00_todo/etaxall-multiagent-audit-todo.md`
2. `03_meta/agent-roster.md`
3. `03_meta/integrity-check.txt`
4. `01_reports/`（A01〜A30）
5. `02_evidence/`（evidence-index + extracted）
6. `04_specs/`（確定申告仕様書4件）

## インデックス
- `manifest.csv`: source_path / pack_path / sha256 / size / modified_at
- `03_meta/source-map.tsv`: コピー元とコピー先の対応表
