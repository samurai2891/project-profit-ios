# Codex Validation Matrix

| タスク ID | 最小検証 | 最終検証 |
| --- | --- | --- |
| `P0-01` | 4 つの 2025 filing pack の `filingDeadline` を目視確認 | deadline lint / unit test で `2026-03-16` を CI 検知可能にする |
| `P0-02` | `blue_cash_basis` 2025/2026 pack と model/exporter の form metadata を照合 | 現金主義の `rootTag / VR / page tag` が official current 仕様に一致 |
| `P0-03` | preview と export で現金主義の主要 3 項目が残ることを確認 | 現金主義の主要金額と経費行が XML に反映され、`missingXmlTag` が発生しない |
| `P0-04` | `.blueCashBasis` が専用 build ルートを通る単体テスト | 現金主義出力が `KOA210` 再利用なしで official current 帳票構造になる |
| `P0-05` | 青色 XML に `KOA210-1..4` のページ分割が現れることを確認 | representative XML が bundled official `KOA210-011.xsd` に通る |
| `P0-06` | 白色 XML に `KOA110-1` と `KOA110-2` が必要に応じて出ることを確認 | representative XML が bundled official `KOA110-012.xsd` に通る |
| `P0-07` | white / blue / cash basis の XML から誤った `ABA...` 混入が無いことを確認 | 帳票別 declarant / address / date / tax year が official タグで出力される |
| `P0-08` | 2025/2026 `blue_general.json` の対象 4 項目の xmlTag を目視確認 | 誤タグ前提のテストが無く、 official 意味と一致した mapping で green |
| `P0-09` | pack lint で direct value が leaf tag のみになることを確認 | 複合要素起因の XSD failure が representative XML で再発しない |
| `P0-10` | `AIK / AIL / AIM / AIN`、`requiredRule`、`KOA110-2` 対応 field の存在確認 | white generated XML が fixture fallback なしで bundled official XSD に通る |
| `P0-11` | `bs_asset_* / bs_liability_* / bs_equity_*` が export payload に残ることを確認 | 青色の貸借対照表が detail を含む `KOA210-4` 構造で出力される |
| `P0-12` | `EtaxXtxExporterTests` と `run_etax_unit_lane.sh` に 3 フォームが揃うことを確認 | `blue_general / white_shushi / blue_cash_basis` の generated XML が全て official XSD に通る |
| `P1-01` | 2025 / 2026 pack 差分と official source 照合結果を文書化 | 2026 各 pack の証跡が残り、未照合時の扱いが明文化される |
| `P1-02` | preview 後に元データを変えた際の再生成ガードを確認 | current data に対する build / validation なし export が不能になる |
| `P1-03` | builder 生成キーと pack 定義キーの差分レポート生成 | 1 件でも未定義キーがあれば CI fail になる |
| `P1-04` | `TaxYearDefinitionLoaderTests` が `blue_cash_basis` を含むことを確認 | pack / builder coverage の穴を loader test で検知できる |
| `P1-05` | `Docs/release/quality/latest.md` の `head_sha` を current HEAD と照合 | quality 個票と checklist が current HEAD で 1 セットに同期する |
| `P1-06` | README / release docs に「必要書類作成まで」「提出機能は対象外」を明記 | docs だけで作れる書類・作れない機能・release 条件が判別できる |

## バッチ別の主検証

| バッチ | 主検証 |
| --- | --- |
| Batch 0 | 追加した Markdown 3 本の目視確認のみ |
| Batch 1 | filing pack deadline の目視確認と deadline test |
| Batch 2 | 現金主義 preview/export/unit test |
| Batch 3 | 青色一般 XML 構造テストと declarant/direct mapping 検証 |
| Batch 4 | 白色 builder/exporter/XSD 検証 |
| Batch 5 | 青色 pack mapping と BS detail export 検証 |
| Batch 6 | `scripts/run_etax_unit_lane.sh` と exporter / loader / coverage 系 test |
| Batch 7 | stale preview/export integration test と 2026 pack 差分監査 |
| Batch 8 | release quality docs と checklist の整合確認 |
