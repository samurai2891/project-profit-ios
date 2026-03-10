# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

ProjectProfit is a native iOS app (Swift/SwiftUI, iOS 17+) for tracking income and expenses across multiple projects. Features include receipt scanning (Vision OCR), recurring transactions, pro-rata allocation, and notification scheduling. All UI strings are in Japanese.

No external package dependencies — purely Apple frameworks (SwiftUI, SwiftData, Vision, PhotosUI, UserNotifications). iOS 26+ optionally uses FoundationModels for AI-powered receipt extraction.

## Build & Test Commands

Project uses **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build
xcodebuild -scheme ProjectProfit -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all tests
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test class
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ProjectProfitTests/DataStoreCRUDTests test

# Run a single test method
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ProjectProfitTests/DataStoreCRUDTests/testAddProject test
```

## Architecture

**MVVM + Service Layer** with SwiftData persistence.

```
ProjectProfitApp (entry point)
  └→ SwiftData modelContainer([PPProject, PPTransaction, PPCategory, PPRecurringTransaction])
      └→ ContentView → MainTabView (tab navigation)
          ├→ Dashboard   ─→ DashboardViewModel
          ├→ Projects    ─→ ProjectsViewModel / ProjectDetailViewModel
          ├→ Transactions ─→ TransactionsViewModel
          ├→ Recurring   ─→ RecurringViewModel
          └→ Settings
```

**Data flow**: `DataStore` is the central `@Observable @MainActor` state container, injected via SwiftUI `@Environment`. Views create ViewModels that reference DataStore for CRUD operations and computed aggregations.

### Key layers

- **Models/** — SwiftData `@Model` classes: `PPProject`, `PPTransaction`, `PPCategory`, `PPRecurringTransaction`. Supporting types: `Allocation`, `ReceiptLineItem`, `ReceiptData`.
- **Services/** — `DataStore` (CRUD, queries, summaries, pro-rata allocation, recurring processing), `ReceiptScannerService` (Vision OCR), `NotificationService`, `ReceiptImageStore` (file-based image persistence under Documents/ReceiptImages/).
- **ViewModels/** — `@Observable` objects that compute filtered/aggregated views from DataStore.
- **Views/** — Organized by feature: Dashboard, Projects, Transactions, Receipt, Recurring, Settings, Components (reusable forms).
- **Utilities/** — Date/currency formatting (`Utilities.swift`), design system colors (`AppColors.swift`).

### Important domain concepts

- **Allocation**: Transactions can be allocated across multiple projects via `Allocation` (projectId, ratio, amount). Two modes: `equalAll` (split evenly across active projects) or `manual` (user-specified projects).
- **Pro-rata**: When a project completes mid-period, recurring transactions are prorated based on the completion date.
- **Recurring transactions**: Auto-generated on schedule (monthly/yearly) with configurable notification timing (sameDay, dayBefore, both, none).

## Testing

XCTest-based. Test files in `ProjectProfitTests/`. Tests use `@testable import ProjectProfit` with in-memory SwiftData model containers.

Key test suites: `DataStoreCRUDTests`, `DataStoreSummaryTests`, `ProRataTests`, `ProRataDataStoreTests`, `RecurringProcessingTests`, `ModelsTests`, `UtilitiesTests`, `LineItemTests`, `ReceiptImageStoreTests`, `TransactionHistoryTests`, `RegexReceiptParserLineItemTests`.

## Commit Convention

Japanese commit messages following conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
