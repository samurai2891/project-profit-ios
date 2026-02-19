import os
import UserNotifications
import SwiftUI

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - NotificationService

@MainActor
@Observable
final class NotificationService {
    private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    private static let sameDayPrefix = "-sameDay"
    private static let dayBeforePrefix = "-dayBefore"

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            AppLogger.notification.error("Authorization request failed: \(error.localizedDescription)")
            isAuthorized = false
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule Notifications

    func scheduleNotifications(for recurring: PPRecurringTransaction) async {
        guard recurring.isActive else { return }
        guard recurring.notificationTiming != .none else { return }

        let nextInfo = getNextRegistrationDate(
            frequency: recurring.frequency,
            dayOfMonth: recurring.dayOfMonth,
            monthOfYear: recurring.monthOfYear,
            isActive: recurring.isActive,
            lastGeneratedDate: recurring.lastGeneratedDate
        )

        guard let registrationInfo = nextInfo else { return }

        let registrationDate = registrationInfo.date

        // Check if the registration date is in skipDates
        let calendar = Calendar.current
        let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: registrationDate) }
        guard !isSkipped else { return }

        let idPrefix = recurring.id.uuidString
        let formattedAmount = formatCurrency(recurring.amount)

        let timing = recurring.notificationTiming

        if timing == .sameDay || timing == .both {
            let identifier = idPrefix + Self.sameDayPrefix
            let title = "定期取引の登録日です"
            let body = "「\(recurring.name)」\(formattedAmount)が本日登録されます"
            let trigger = buildCalendarTrigger(for: registrationDate, at: 9, minute: 0)

            await scheduleNotification(identifier: identifier, title: title, body: body, trigger: trigger)
        }

        if timing == .dayBefore || timing == .both {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: registrationDate) else { return }

            // Only schedule if the day-before date is today or in the future
            let today = todayDate()
            guard dayBefore >= today else { return }

            let identifier = idPrefix + Self.dayBeforePrefix
            let title = "明日は定期取引の登録日です"
            let body = "「\(recurring.name)」\(formattedAmount)が明日登録されます"
            let trigger = buildCalendarTrigger(for: dayBefore, at: 9, minute: 0)

            await scheduleNotification(identifier: identifier, title: title, body: body, trigger: trigger)
        }
    }

    // MARK: - Cancel Notifications

    func cancelNotifications(for recurringId: UUID) async {
        let idPrefix = recurringId.uuidString
        let identifiers = [
            idPrefix + Self.sameDayPrefix,
            idPrefix + Self.dayBeforePrefix,
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Reschedule All

    func rescheduleAll(recurringTransactions: [PPRecurringTransaction]) async {
        center.removeAllPendingNotificationRequests()

        for recurring in recurringTransactions {
            guard recurring.isActive else { continue }
            guard recurring.notificationTiming != .none else { continue }
            await scheduleNotifications(for: recurring)
        }
    }

    // MARK: - Scheduled Count

    func scheduledNotificationCount() async -> Int {
        let requests = await center.pendingNotificationRequests()
        return requests.count
    }

    // MARK: - Private Helpers

    private func buildCalendarTrigger(for date: Date, at hour: Int, minute: Int) -> UNCalendarNotificationTrigger {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        trigger: UNCalendarNotificationTrigger
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            AppLogger.notification.error("Failed to schedule notification '\(identifier)': \(error.localizedDescription)")
        }
    }
}
