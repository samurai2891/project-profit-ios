#!/bin/sh
set -eu

ROOT="/Users/yutaro/project-profit-ios"

xcodebuild test \
  -project "$ROOT/ProjectProfit.xcodeproj" \
  -scheme ProjectProfit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ProjectProfitTests/LedgerDataStoreTests/testMaterializeLedgerXLSXGoldenFixtures

exec python3 "$ROOT/scripts/verify_generated_ledger_xlsx_golden.py"
