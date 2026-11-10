import os

/// Loggers. **Never log clipboard contents**: only ids, kinds, types, sizes, and reasons.
enum Log {
    static let app = Logger(subsystem: "com.omar.clipdock", category: "app")
    static let capture = Logger(subsystem: "com.omar.clipdock", category: "capture")
    static let storage = Logger(subsystem: "com.omar.clipdock", category: "storage")
    static let popup = Logger(subsystem: "com.omar.clipdock", category: "popup")
    static let paste = Logger(subsystem: "com.omar.clipdock", category: "paste")
    static let translate = Logger(subsystem: "com.omar.clipdock", category: "translate")
}
