import Darwin

/// Secure input (password fields, Terminal's "Secure Keyboard Entry") blocks synthetic
/// keystrokes. `IsSecureEventInputEnabled()` is exported by HIToolbox but has no header in
/// SDK 26.2, so it's looked up at runtime. If the symbol is missing, this reports `false`.
enum SecureInput {
    private typealias Function = @convention(c) () -> UInt8

    private static let function: Function? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let symbol = dlsym(rtldDefault, "IsSecureEventInputEnabled") else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    static var isAvailable: Bool { function != nil }

    static var isEnabled: Bool {
        guard let function else { return false }
        return function() != 0
    }
}
