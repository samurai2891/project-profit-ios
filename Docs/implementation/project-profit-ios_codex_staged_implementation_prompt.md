# project-profit-ios Codex向け 段階実装版プロンプト

以下をそのまま Codex に渡してください。

---

あなたは外資系開発会社の Staff / Principal クラスの iOS エンジニア兼シニアPMです。  
対象リポジトリは **`https://github.com/samurai2891/project-profit-ios`** です。  
目的は、**現行仕様を前提に、リリース前に必要な作業だけを段階的に実装・修正・統合し、リリース判定できる状態へ持っていくこと**です。

## 0. 絶対条件

- **推測しないこと。事実のみで判断すること。**
- **公開 `main` と、添付されたレビュー資料・計画資料・Excel資料を必ず読むこと。**
- **README が root に無い場合は、無いことを事実として扱い、`Docs/specs/SPEC.md`・release docs・About 表記でプロジェクト理解を行うこと。README を捏造しないこと。**
- **リリース後対応は一切やらないこと。リリース前に必要な作業のみを対象にすること。**
- **不要なリファクタや設計美化はしないこと。release blocker / release completeness に効く変更だけ行うこと。**
- **各フェーズは必ずそこで止まり、変更ファイル・テスト結果・未解消点をまとめてから次フェーズへ進むこと。**
- **1フェーズで複数テーマを跨いで拡散しないこと。**
- **BS / PL は新規デザインしないこと。添付の `project-profit-ios_bs_pl_analysis_template.xlsx` を正式原本テンプレートとして採用すること。**
- **帳簿原本は添付の `project-profit-ios_templates_consolidated_spreadsheet.xlsx` と `project-profit-ios_excel_template_task_table (1).md` を基準にすること。**
- **できた / できないを曖昧に書かず、ファイル・テスト・CI・ドキュメント単位で完了を示すこと。**
- **各フェーズで git diff を小さく保ち、変更理由を説明できる単位で進めること。**

## 1. 入力資料（必ず読むこと）

以下を正本資料として扱うこと。

1. 公開リポジトリ `project-profit-ios`
2. `project-profit-ios_release_plan_verification_corrected (1).md`
3. `project-profit-ios_excel_template_task_table (1).md`
4. `project-profit-ios_release_plan_p0-p2.md` または同等の P0/P1/P2 計画資料
5. `project-profit-ios_release_preflight_code_review.md`
6. `project-profit-ios_bs_pl_analysis_template.xlsx`
7. `project-profit-ios_templates_consolidated_spreadsheet.xlsx`

## 2. 優先順位（ソースオブトゥルース）

競合があった場合は次の優先順位で判断すること。

1. ユーザーの最新指示
2. 現在の公開 `main` のコード
3. `project-profit-ios_release_plan_verification_corrected (1).md`
4. `project-profit-ios_excel_template_task_table (1).md`
5. `Docs/specs/SPEC.md`
6. `Docs/release/quality/*` と `release_review_implementation_status.md`
7. `project-profit-ios_bs_pl_analysis_template.xlsx`
8. `project-profit-ios_templates_consolidated_spreadsheet.xlsx`

## 3. Codex の動作ルール

- 各フェーズ開始時に、**今回の変更対象ファイル一覧**を宣言すること。
- 各フェーズでは、**実装 → テスト/検証 → ドキュメント同期 → フェーズ結果報告**の順で進めること。
- 各フェーズ終了時に、次の 4 つを必ず出すこと。
  1. 変更ファイル一覧
  2. 実施したテスト / 検証
  3. 未解消事項
  4. 次フェーズへ進んでよいかの判断
- **次フェーズに入る前に、必ず前フェーズの完了条件を確認すること。**
- もし前フェーズの完了条件を満たせない場合は、そこで止まり、追加で必要な事実・修正点を明示すること。
- **未確認のまま「完了」と書かないこと。**
- 変更内容を説明するときは、必ず **ファイル名 + 変更意図 + なぜ今必要か** をセットで書くこと。

## 4. 最終ゴール

以下を満たすこと。

### ゴールA: リリースカタログの不整合解消

- `BooksWorkspaceView.swift` と `BooksWorkspaceViewTests.swift` の差分解消
- `交通費精算書` の release / legacy 二重化整理
- `交通費精算書` の release 表示なのに legacy read-only 依存している構造の整理
- `棚卸台帳` の扱いを仕様・UI・export catalog で一致させる

### ゴールB: 固定資産 2 帳票の完了

- `fixedAssetRegister`
- `fixedAssetDepreciation`

上記を UI / export / template mapping / tests まで end-to-end で成立させる。

### ゴールC: BS / PL 正式採用と実装接続

- `project-profit-ios_bs_pl_analysis_template.xlsx` を正式原本テンプレートとして採用
- 既存会計導線から B/S・P/L へ数値が流れるようにする
- 勘定科目マスターと trial balance / BS / PL の接続を成立させる
- 新規の見た目設計はしない

### ゴールD: 帳簿原本テンプレート接続

- `project-profit-ios_templates_consolidated_spreadsheet.xlsx` の `Form / Mapping / SourceNotes` を参照し、帳簿原本と exporter / mapping / tests を接続する

### ゴールE: release gate の現実化

- `BooksWorkspaceViewTests`
- `ExportCoordinatorTests`
- 主要 UI flow tests
- 固定資産 2 帳票関連テスト
- BS / PL 接続確認

を release gate またはそれに準ずる統合テスト対象に入れる

### ゴールF: HEAD と証跡の一致

- release candidate の `head_sha` を 1 本に固定できるようにする
- workflow / docs / release quality の参照先を current candidate に合わせる

## 5. 必ず読むべきファイル

- `Docs/specs/SPEC.md`
- `Docs/release/quality/README.md`
- `Docs/release/quality/latest.md`
- `release_review_implementation_status.md`
- `ProjectProfit/Services/ExportCoordinator.swift`
- `ProjectProfit/Ledger/Services/LedgerExcelExportService.swift`
- `ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift`
- `ProjectProfitTests/ExportCoordinatorTests.swift`
- `ProjectProfitTests/BooksWorkspaceViewTests.swift`
- `ProjectProfitTests/EtaxExportViewModelTests.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `ProjectProfitUITests/WithholdingApprovalUITests.swift`
- `.github/workflows/release-quality.yml`
- `.github/workflows/etax-ci.yml`
- `scripts/run_release_quality_lane.sh`

BS / PL については以下も必ず使うこと。

- `project-profit-ios_bs_pl_analysis_template.xlsx`
- 既存の勘定科目マスター関連ファイル
- `project-profit-ios_templates_consolidated_spreadsheet.xlsx`

## 6. フェーズ分割（必ずこの順に進める）

# Phase 0: 現状固定と読み込み

## 目的
- 事実の読み違いをなくす
- 対象ファイルと canonical list を固定する
- 変更前のベースラインを明文化する

## このフェーズでやること
1. repo を読み、root README の有無を確認する
2. 次の canonical list を作る
   - release books 一覧
   - legacy / compat 一覧
   - export target 一覧
   - fixed asset 関連 target 一覧
   - BS / PL 関連ファイル一覧
3. 添付資料の内容と current `main` の差分を短くまとめる
4. 今回の変更対象ファイル一覧を作る

## 変更してよいファイル
- なし（原則 read-only）
- 必要なら作業メモのみ。ただし本番コード変更は禁止

## 完了条件
- 今回の対象ファイル一覧がある
- canonical list がある
- README 有無が確認済み
- 次フェーズで直すべき差分が箇条書きで出ている

## フェーズ終了時の出力
- `Phase 0 Summary`
- canonical list
- 次フェーズ対象ファイル一覧

---

# Phase 1: カタログ差分修正（Books / transportation / inventory）

## 目的
release surface の不整合を最小差分で解消する

## このフェーズでやること
1. `BooksWorkspaceView.swift` と `BooksWorkspaceViewTests.swift` の差分を解消する
2. `交通費精算書` の release / legacy 二重表示を整理する
3. `棚卸台帳` の扱いを spec / UI / export catalog と一致させる
4. docs / tests / UI 名称のズレを埋める

## 変更対象の主ファイル
- `ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift`
- `ProjectProfitTests/BooksWorkspaceViewTests.swift`
- 必要に応じて catalog 関連 docs

## 禁止事項
- ここでは固定資産や BS/PL にはまだ手を広げない
- transportation の domain 深掘りは次フェーズに回す

## 完了条件
- `BooksWorkspaceView` と tests の差分がない
- `交通費精算書` の見え方が 1 つの方針に揃っている
- `棚卸台帳` の扱いが spec / UI / tests で一致している

## フェーズ終了時の出力
- 変更ファイル一覧
- 実行したテスト
- catalog 差分の解消内容
- 次フェーズ対象ファイル一覧

---

# Phase 2: transportation 正式導線整理

## 目的
release 表示されている transportation を、内部構造も含めて release-ready にする

## このフェーズでやること
1. release 側 transportation route が legacy read-only 依存している箇所を特定する
2. 正式 route を 1 本に整理する
3. どうしても legacy を残す場合は、release path と compat path を明確に分離する
4. export / tests / docs をその決定に合わせる

## 変更対象の主ファイル
- `BooksWorkspaceView.swift`
- `ExportCoordinator.swift`
- transportation 関連 test / docs

## 禁止事項
- ここでは xlsx scope や BS/PL にはまだ触れない
- UI 見た目改善に逃げない。route / domain 整理だけ行う

## 完了条件
- transportation の正式 route が 1 本に説明できる
- release path が legacy read-only を前提にしない、または明示的な互換導線として隔離されている
- export / tests / docs がその決定に一致している

## フェーズ終了時の出力
- route 変更内容
- 依存除去 or 互換隔離の説明
- 実行したテスト

---

# Phase 3: 固定資産 2 帳票完成

## 目的
`fixedAssetRegister` と `fixedAssetDepreciation` を end-to-end で完成させる

## このフェーズでやること
1. `fixedAssetRegister` と `fixedAssetDepreciation` を別帳票として明示的に扱う
2. UI / exporter / tests / template mapping を揃える
3. 原本比較の前提となる mapping を追加する
4. 既存の部分実装状態を解消する

## 変更対象の主ファイル
- fixed asset 関連 UI
- `ExportCoordinator.swift`
- 必要な exporter / mapping / tests
- 必要な docs

## 禁止事項
- ここでは B/S・P/L にはまだ触れない
- 固定資産以外の帳票改善に広げない

## 完了条件
- fixed asset 2帳票が UI / export / mapping / tests で整合している
- 部分実装扱いにしていた論点へ対処した証跡がある
- 少なくとも targeted tests が通る

## フェーズ終了時の出力
- fixed asset 変更ファイル一覧
- 追加/修正テスト一覧
- 原本比較前提の mapping 内容

---

# Phase 4: BS / PL 正式採用と接続

## 目的
`project-profit-ios_bs_pl_analysis_template.xlsx` を正式原本として採用し、実装へ接続する

## このフェーズでやること
1. テンプレートの構造を確認する
   - `COA_Master`
   - `Journal_Input`
   - `TB_Detail`
   - `BS_Map`
   - `PL_Map`
   - `BS_Form`
   - `PL_Form`
2. 既存コードの会計導線から trial balance / BS / PL へ流すための mapping を作る
3. 勘定科目マスターの不足がある場合は、最小限で補強する
4. B/S・P/L を正式原本採用として docs に反映する
5. report export (`BS / PL / trial balance / journal / ledger / fixed assets`) を `ExportCoordinator` から `.xlsx` 正式対応にする

## 変更対象の主ファイル
- 勘定科目マスター関連ファイル
- B/S・P/L 接続コード
- 必要な mapping / tests / docs

## 禁止事項
- B/S・P/L の見た目を新規デザインしない
- 上場企業向け新様式を別途作らない

## 完了条件
- B/S・P/L が指定テンプレートを正式原本として扱われる
- 勘定科目 → trial balance → BS/PL の接続が説明できる
- 接続結果を確認できるテストまたは検証結果がある

## フェーズ終了時の出力
- 接続に使ったファイル一覧
- 勘定科目変更の有無
- BS / PL 反映確認結果

---

# Phase 5: 帳簿原本テンプレート接続

## 目的
帳簿原本スプレッドシートを exporter / mapping / tests に接続する

## このフェーズでやること
1. `project-profit-ios_templates_consolidated_spreadsheet.xlsx` を参照し、帳簿ごとの `Form / Mapping / SourceNotes` をコードに反映する
2. exporter の列順・表示名・出力順とテンプレートを一致させる
3. xlsx が release scope に含まれるかを docs / code 上で整理する

## 変更対象の主ファイル
- exporter / mapping / tests
- 原本関連 docs

## 禁止事項
- ここで scope 外機能を増やさない
- xlsx を勝手に release 必須にしない

## 完了条件
- 帳簿原本テンプレートと exporter / mapping が一致している
- xlsx の扱いが docs / code / tests で説明できる

## フェーズ終了時の出力
- 原本接続の変更一覧
- 帳簿ごとの対応状況表

---

# Phase 6: release gate / CI / Release 構成の整合化

## 目的
release surface を gate できる CI / quality lane にする

## このフェーズでやること
1. `BooksWorkspaceViewTests` を gate に入れる
2. `ExportCoordinatorTests` を gate に入れる
3. 主要 UI flow tests を gate に入れる
4. `run_release_quality_lane.sh` と workflow を release candidate に合わせる
5. 可能な範囲で Release 構成の検証を追加する

## 変更対象の主ファイル
- `.github/workflows/release-quality.yml`
- `.github/workflows/etax-ci.yml`
- `scripts/run_release_quality_lane.sh`
- 関連 docs

## 禁止事項
- 単に test を増やすだけで、gate に乗せないまま終わらせない

## 完了条件
- 今回修正した重要差分を gate が拾える
- 実行結果が docs / summary に反映される

## フェーズ終了時の出力
- 変更した workflow / script 一覧
- 追加された gate 一覧
- 実行結果

---

# Phase 7: docs / HEAD / 証跡同期

## 目的
current release candidate と docs / quality / review を一致させる

## このフェーズでやること
1. `Docs/specs/SPEC.md` と current implementation の差分を埋める
2. release review / quality docs を current candidate ベースで更新する
3. B/S・P/L テンプレート採用を release docs に反映する
4. 原本Excelタスク表の完了状況を docs に反映する
5. current HEAD と証跡の対応が 1 本に読める状態にする

## 変更対象の主ファイル
- `Docs/specs/SPEC.md`
- `Docs/release/quality/*`
- `release_review_implementation_status.md`
- 必要な release summary docs

## 禁止事項
- docs だけ直してコード未反映にしない
- 根拠のない完了宣言を書かない

## 完了条件
- docs / code / tests / release review が同期している
- current release candidate の HEAD と証跡の関係が説明できる

## フェーズ終了時の出力
- 更新した docs 一覧
- HEAD / 証跡対応表
- 最終未解消点（あれば）

---

## 7. 作業対象から除外するもの

- リリース後改善
- 新規要件追加
- 将来用の大規模リファクタ
- README の新規創作
- B/S・P/L の新規デザイン案作成
- e-Tax の scope 外 form/year の拡張（明示的根拠が無い限り）

## 8. 変更時のルール

- 変更は必ずファイル単位で理由を残すこと
- 仕様差分を埋める変更では、**コード・テスト・docs を同時に直すこと**
- 1つの差分を直して別の差分を増やさないこと
- 既存 UI 名称・帳票名称をむやみに変えないこと。変えるなら全出現箇所を揃えること
- 固定資産、BS、PL、支払調書のような重い帳票は sample / mapping / test までセットで変更すること

## 9. 最終提出物

全フェーズ完了後、以下をまとめて提出すること。

1. 変更ファイル一覧（フェーズ別）
2. 各変更の理由
3. release blocker がどう解消されたかの対応表
4. 未解消項目がある場合は、その理由と release 可否判定
5. 実行したテスト一覧
6. 追加 / 修正した release gate 一覧
7. BS / PL テンプレート接続結果
8. 帳簿原本テンプレートとの整合結果
9. current HEAD と証跡の対応表

## 10. 最後に

このタスクの本質は、**「新しく何かを発明すること」ではなく、「いま既に存在する仕様・帳票・導線・テンプレート・テスト・証跡を矛盾なく1本化して、リリース可能状態へ持っていくこと」**です。  
したがって、必ず **事実ベース・差分ベース・ファイルベース** で進めてください。  
不明点があっても推測で埋めず、コードと添付資料の整合だけで閉じてください。

---

以上の条件で、**Phase 0 から順番に実装を開始してください。各フェーズ終了時に必ず停止し、結果をまとめてください。**
