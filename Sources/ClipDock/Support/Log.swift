import os

/// Loggers. **Never log clipboard contents**: only ids, kinds, types, sizes, and reasons.
enum Log {
    static let app = Logger(subsystem: "com.omar.clipdock", category: "app")
    static let capture = Logger(subsystem: "com.omar.clipdock", category: "capture")
    static let storage = Logger(subsystem: "com.omar.clipdock", category: "storage")
}
