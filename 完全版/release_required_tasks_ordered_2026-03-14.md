# ProjectProfit リリース必須タスク整理
作成日: 2026-03-14  
対象 HEAD: `fe19501`

## 目的

- `release_fact_audit_2026-03-14.md` で確認できた事実だけをもとに、リリースまでに実施が必要な作業を依存順に並べ直す。
- 推測は含めず、`不具合再現` `未証明` `証跡不足` `説明不整合` を解消する順に整理する。

## 最優先で着手する順番

### 1. 申告前チェックの仮勘定残高検知を修正する

- 目的:
  - `仮勘定残高があると申告出力を止める` 挙動を現HEADで成立させる。
- 背景事実:
  - `ProjectProfitTests/FilingPreflightUseCaseTests/testExportPreflightDetectsSuspenseBalance` が 2026-03-14 再実行で失敗した。
  - `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift` は仮勘定判定に canonical trial balance だけを使っている。
- 主対象:
  - `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift`
  - `ProjectProfitTests/FilingPreflightUseCaseTests.swift`
- 完了条件:
  - failing test が green になる。
  - `仮勘定残高がある場合は export blocker になる` ことをテストで再確認できる。

### 2. 申告前チェック修正後に申告系代表テストを再実行する

- 目的:
  - blocker 修正が既存の申告出力フローを壊していないことを確認する。
- 背景事実:
  - 同じ再実行では `EtaxExportViewModelTests` 11件と `WithholdingFlowE2ETests` 1件は通過している。
- 主対象:
  - `ProjectProfitTests/FilingPreflightUseCaseTests.swift`
  - `ProjectProfitTests/EtaxExportViewModelTests.swift`
  - `ProjectProfitTests/WithholdingFlowE2ETests.swift`
- 完了条件:
  - 上記3スイートがすべて green になる。

### 3. 現金主義を UI から選べるようにするか、非対応であることを UI 仕様に揃える

- 目的:
  - `ViewModel / builder では存在するが画面から到達できない` 状態を解消する。
- 背景事実:
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift` と `ProjectProfit/Services/FormEngine.swift` は `.blueCashBasis` を扱う。
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift` でも現金主義が選べる。
  - ただし `ProjectProfit/Views/Accounting/EtaxExportView.swift` の Picker は `青色申告` と `白色申告` しか表示しない。
- 主対象:
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift`
  - 必要なら関連 ViewModel / テスト
- 完了条件:
  - UI と内部仕様の不一致がなくなる。
  - 現金主義をサポートするなら UI から選択できる。
  - サポートしないなら内部ロジック・表示・仕様書の整合が取れる。

### 4. FormEngine の legacy 依存を整理する

- 目的:
  - 申告生成の canonical 一本化を進める。
- 背景事実:
  - `ProjectProfit/Services/FormEngine.swift` に `legacyAccountsById` と `DataStore` 直結 overload が残る。
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift` は `legacyAccountsById` を使う。
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift` は `candidate.legacySnapshot` を使う。
- 主対象:
  - `ProjectProfit/Services/FormEngine.swift`
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
- 完了条件:
  - 申告 builder の main path が legacy 情報なしで成立する。
  - 旧互換が残る場合も migration / compat 用途へ限定される。

### 5. 申告 builder 整理後に Form / e-Tax テストを再実行する

- 目的:
  - 申告生成変更後の後退を防ぐ。
- 主対象:
  - `ProjectProfitTests/FormEngineTests.swift`
  - `ProjectProfitTests/ShushiNaiyakushoBuilderTests.swift`
  - `ProjectProfitTests/EtaxExportViewModelTests.swift`
- 完了条件:
  - 申告フォーム生成系テストが green になる。

## リリース判定のために次に行う順番

### 6. current HEAD 向けの release quality 証跡を更新する

- 目的:
  - curated artifact と現HEADの不一致を解消する。
- 背景事実:
  - `Docs/release_quality/latest.md` は 2026-03-07 / `86b7b08...` を指す。
  - 現HEAD は `fe19501`。
  - `Docs/release_quality/books.md` と `Docs/release_quality/forms.md` には 2026-03-14 の個票がある。
- 主対象:
  - `Docs/release_quality/latest.md`
  - `Docs/release_quality/latest-lane.md`
  - checklist 対象 lane の個票
- 完了条件:
  - current HEAD に対する fully-green snapshot が repo 内で追える。

### 7. release checklist の対象 lane を current HEAD で揃えて再確認する

- 目的:
  - `release 可否` を checklist 基準で判断できる状態にする。
- 背景事実:
  - `Docs/release_checklist.md` は curated snapshot と lane 個票を正本としている。
- 主対象:
  - `Docs/release_checklist.md`
  - `Docs/release_quality/latest.md`
  - lane 個票
- 完了条件:
  - checklist 対象の green 根拠が current HEAD と一致する。

## リリース判断の精度を上げるための確認順

### 8. 固定資産 / 棚卸を 2026-03-14 時点で再検証する

- 目的:
  - 今回 `未確認/未証明` とした領域を減らす。
- 背景事実:
  - 実装ファイルとテストファイルは存在するが、今回の再実行対象外だった。
- 主対象:
  - `ProjectProfitTests/FixedAssetWorkflowUseCaseTests.swift`
  - `ProjectProfitTests/InventoryWorkflowUseCaseTests.swift`
- 完了条件:
  - current HEAD で representative test の結果を追加記録できる。

### 9. 定期取引の release 観点を再確認する

- 目的:
  - 現在 `部分実装` と置いている recurring のリリース可否を明確にする。
- 背景事実:
  - 今回の監査では recurring 専用の再実行をしていない。
- 主対象:
  - recurring 関連テスト
  - recurring preview / approve の main path
- 完了条件:
  - `実装済み` か `部分実装` かを current HEAD の実行結果つきで判断できる。

## ドキュメント整合の修正順

### 10. 「外部 package なし」の説明を現コードに合わせて直す

- 目的:
  - repo 説明と実体の不一致をなくす。
- 背景事実:
  - `project.yml` に `libxlsxwriter` の SwiftPM dependency がある。
  - `xcodebuild` 実行でも `libxlsxwriter @ 1.2.4` が解決された。
- 主対象:
  - `AGENTS.md`
  - 関連する説明文書
- 完了条件:
  - 外部依存に関する説明が現コードと一致する。

### 11. release 監査レポートを更新して最終判定を確定する

- 目的:
  - 修正後の状態を最終成果物として残す。
- 主対象:
  - `完全版/release_fact_audit_2026-03-14.md`
- 完了条件:
  - blocker 解消状況
  - current HEAD 向け test / artifact 結果
  - `確定申告できる` と言える範囲 / 言えない範囲
  - 上記が 2026-03-14 以降の実データで更新されている

## 依存関係つきの実施順まとめ

1. `申告前チェックの仮勘定残高検知を修正`
2. `申告系代表テストを再実行`
3. `現金主義 UI 到達性の不一致を解消`
4. `FormEngine / Shushi / CashBasis の legacy 依存を整理`
5. `Form / e-Tax テストを再実行`
6. `release quality 証跡を current HEAD 向けに更新`
7. `release checklist 対象 lane を current HEAD で揃える`
8. `固定資産 / 棚卸の再検証`
9. `定期取引の再検証`
10. `外部依存の説明を修正`
11. `監査レポートを更新して最終判定`

## 先に着手すると効率が悪いもの

- `release quality latest.md` 更新
  - blocker 修正前に更新すると、再度取り直しが必要になる。
- `外部依存の説明修正`
  - release blocker ではないため後回しでよい。
- `固定資産 / 棚卸の再検証`
  - 先に申告 blocker を直さないと、最終判定に必要な主問題が残る。
