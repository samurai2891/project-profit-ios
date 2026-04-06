# ProjectProfit

ProjectProfit は、個人事業主向けの native iOS 会計アプリです。  
SwiftUI / SwiftData ベースで、取引入力、案件別収支、帳簿・帳票 export、e-Tax 向け導線、証憑管理までを 1 つのアプリにまとめています。

## 概要

- 対応プラットフォーム: iOS 17+
- 主な技術: SwiftUI, SwiftData, Vision, UserNotifications, `libxlsxwriter`
- アプリ内の主要領域:
  - 取引入力と承認キュー
  - 案件別収支と履歴
  - 帳簿ワークスペース
  - 帳票 export
  - e-Tax / filing 補助
  - 書類台帳と保持統制

## Official Export Matrix

official source of truth は [`Docs/specs/SPEC.md`](/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md) です。

### 帳簿ワークスペース target

以下の 11 帳簿は official target として `CSV / PDF / XLSX` をサポートします。

- 現金出納帳
- 預金出納帳
- 売掛帳
- 買掛帳
- 経費帳
- 総勘定元帳
- 仕訳帳
- 白色申告用 簡易帳簿
- 交通費精算書
- 固定資産台帳
- 固定資産台帳 兼 減価償却計算表

### 帳票 target

以下の 7 帳票は official target として `.xlsx` をサポートします。

- 損益計算書
- 貸借対照表
- 残高試算表
- 仕訳帳
- 総勘定元帳
- 固定資産台帳
- 減価償却明細表

`legacyLedgerBook` は互換導線であり、official export matrix の正本には含めません。

## Source Of Truth

- 仕様書: [`Docs/specs/SPEC.md`](/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md)
- release 判定正本: [`Docs/release/checklist.md`](/Users/yutaro/project-profit-ios/Docs/release/checklist.md)
- staged release タスク: [`Docs/release/project-profit-ios_release_tasks_checklist_2026-04-06.md`](/Users/yutaro/project-profit-ios/Docs/release/project-profit-ios_release_tasks_checklist_2026-04-06.md)
- Excel template 正本: [`ProjectProfit/Ledger/Resources/excel_templates/README.md`](/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Resources/excel_templates/README.md)

## Build And Test

この repo は XcodeGen を使います。

```bash
xcodegen generate
xcodebuild -scheme ProjectProfit -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Release Gate

release 判定は [`Docs/release/checklist.md`](/Users/yutaro/project-profit-ios/Docs/release/checklist.md) と `Release Quality` workflow を正本にします。

主要 gate は次です。

- `xcodegen-sync`
- `simulator-health`
- `release-build`
- `golden-baseline`
- `canonical-e2e`
- `migration-rehearsal`
- `performance-gate`
- `books`
- `forms`
- `xlsx-verify`

lane ごとの current evidence は [`Docs/release/quality`](/Users/yutaro/project-profit-ios/Docs/release/quality) 配下で管理します。

## Repo 外で管理するもの

この repo だけでは確定しない運用項目もあります。

- App Store Connect の設定値
- support URL の実値
- 法令適合の最終対外証明
- 実本番の配布・審査オペレーション

repo 内で確認できる release 可否は、あくまで code / docs / evidence artifacts の範囲です。
