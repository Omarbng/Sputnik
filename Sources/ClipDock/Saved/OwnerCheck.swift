import Foundation
import LocalAuthentication

/// Asks for Touch ID (or the Mac's login password) before a secret is pasted or copied.
enum OwnerCheck {
    /// macOS shows "Sputnik is trying to <reason>."
    static func confirm(_ reason: String) async -> Bool {
        #if CLIPDOCK_TEST_BUILD
        // Test builds only (`CLIPDOCK_TEST_BUILD=1 ./run.sh`), never the everyday build.
        if ProcessInfo.processInfo.environment["CLIPDOCK_FAKE_AUTH"] == "1" {
            Log.paste.notice("unlock skipped (test build)")
            return true
        }
        #endif
        let context = LAContext()
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return true
        } catch {
            Log.paste.notice("unlock refused code=\((error as NSError).code, privacy: .public)")
            return false
        }
    }
}
