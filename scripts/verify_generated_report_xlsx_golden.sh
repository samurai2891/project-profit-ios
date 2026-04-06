#!/bin/sh
set -eu

ROOT="/Users/yutaro/project-profit-ios"

xcodebuild test \
  -project "$ROOT/ProjectProfit.xcodeproj" \
  -scheme ProjectProfit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ProjectProfitTests/ExportCoordinatorTests/testMaterializeReportXLSXGoldenFixtures

exec python3 "$ROOT/scripts/verify_generated_report_xlsx_golden.py"
