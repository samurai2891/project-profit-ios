import os

enum AppLogger {
    private static let subsystem = "com.projectprofit"

    static let dataStore = Logger(subsystem: subsystem, category: "DataStore")
    static let notification = Logger(subsystem: subsystem, category: "Notification")
    static let general = Logger(subsystem: subsystem, category: "General")
}
