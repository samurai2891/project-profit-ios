import SwiftData
import SwiftUI

// MARK: - DataStore Year Lock Extension

extension DataStore {

    // MARK: - Year Lock Guard

    /// 指定日付の年度がロック済みか確認し、ロック済みならエラーを設定してtrueを返す
    func isYearLocked(for date: Date) -> Bool {
        let year = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        return isYearLocked(year)
    }

    /// 指定年度がロック済みか確認し、ロック済みならエラーを設定してtrueを返す
    func isYearLocked(_ year: Int) -> Bool {
        if yearLockState(for: year) != .open {
            lastError = .yearLocked(year: year)
            return true
        }
        return false
    }

    // MARK: - Graduated Lock Checks

    /// 通常仕訳の登録が不可か判定（softCloseまでは許可、taxClose以降は不可）
    func cannotPostNormalEntry(for date: Date) -> Bool {
        let year = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        return cannotPostNormalEntry(forYear: year)
    }

    func cannotPostNormalEntry(forYear year: Int) -> Bool {
        let state = yearLockState(for: year)
        if !state.allowsNormalPosting {
            lastError = .yearLocked(year: year)
            return true
        }
        return false
    }

    /// 決算整理仕訳の登録が不可か判定（taxCloseまでは許可、filed以降は不可）
    func cannotPostAdjustingEntry(for date: Date) -> Bool {
        let year = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        return cannotPostAdjustingEntry(forYear: year)
    }

    func cannotPostAdjustingEntry(forYear year: Int) -> Bool {
        let state = yearLockState(for: year)
        if !state.allowsAdjustingEntries {
            lastError = .yearLocked(year: year)
            return true
        }
        return false
    }

    func yearLockState(for year: Int) -> YearLockState {
        if let canonicalState = persistedYearLockState(for: year) {
            return canonicalState
        }
        return .open
    }

    // MARK: - Lock / Unlock

#if DEBUG
    /// 指定年度をロックする
    func lockFiscalYear(_ year: Int) {
        forceUpdateYearLockState(.finalLock, for: year)
    }

    /// 指定年度のロックを解除する
    func unlockFiscalYear(_ year: Int) {
        forceUpdateYearLockState(.open, for: year)
    }

    @discardableResult
    func transitionFiscalYearState(_ state: YearLockState, for year: Int) -> Bool {
        ensureCanonicalProfileLoadedForYearLock()
        guard let businessId = businessProfile?.id else {
            let error = AppError.invalidInput(message: "申告者情報が未設定のため年度状態を更新できません")
            AppLogger.dataStore.warning("\(error.localizedDescription)")
            lastError = error
            return false
        }

        do {
            let fallbackProfile = currentTaxYearProfile?.taxYear == year ? currentTaxYearProfile : nil
            let updated = try TaxYearStateUseCase(modelContext: modelContext).transitionYearLock(
                businessId: businessId,
                taxYear: year,
                targetState: state,
                fallbackProfile: fallbackProfile
            )
            if currentTaxYearProfile?.taxYear == year {
                currentTaxYearProfile = updated
            }
            lastError = nil
            return true
        } catch {
            AppLogger.dataStore.error("Validated year lock update failed: year=\(year), state=\(state.rawValue), error=\(error.localizedDescription)")
            lastError = .saveFailed(underlying: error)
            modelContext.rollback()
            return false
        }
    }
#endif

    private func persistedYearLockState(for year: Int) -> YearLockState? {
        if let currentTaxYearProfile, currentTaxYearProfile.taxYear == year {
            return currentTaxYearProfile.yearLockState
        }
        guard let businessId = businessProfile?.id else {
            return nil
        }
        do {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == year
                }
            )
            let entity = try modelContext.fetch(descriptor).first
            return entity.flatMap { YearLockState(rawValue: $0.yearLockStateRaw) }
        } catch {
            AppLogger.dataStore.warning("Year lock state lookup failed: year=\(year), error=\(error.localizedDescription)")
            return nil
        }
    }

    private func forceUpdateYearLockState(_ state: YearLockState, for year: Int) {
        ensureCanonicalProfileLoadedForYearLock()
        guard let businessId = businessProfile?.id else {
            AppLogger.dataStore.warning("Year lock update skipped: canonical business profile unavailable")
            return
        }

        do {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == year
                }
            )

            if let entity = try modelContext.fetch(descriptor).first {
                entity.yearLockStateRaw = state.rawValue
                entity.updatedAt = Date()
                if currentTaxYearProfile?.taxYear == year {
                    currentTaxYearProfile = TaxYearProfileEntityMapper.toDomain(entity)
                }
            } else {
                let profile = TaxYearProfile(
                    businessId: businessId,
                    taxYear: year,
                    yearLockState: state,
                    taxPackVersion: (try? BundledTaxYearPackProvider(bundle: .main).packSync(for: year).version)
                        ?? "\(year)-v1"
                )
                modelContext.insert(TaxYearProfileEntityMapper.toEntity(profile))
                if currentTaxYearProfile?.taxYear == year {
                    currentTaxYearProfile = profile
                }
            }

            save()
        } catch {
            AppLogger.dataStore.error("Year lock update failed: year=\(year), error=\(error.localizedDescription)")
            lastError = .saveFailed(underlying: error)
            modelContext.rollback()
        }
    }

    private func ensureCanonicalProfileLoadedForYearLock() {
        guard businessProfile == nil else {
            return
        }
        runLegacyProfileMigrationIfNeeded()
        refreshCanonicalProfileCache()
    }
}
