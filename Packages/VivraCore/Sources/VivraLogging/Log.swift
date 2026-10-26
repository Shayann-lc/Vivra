#if canImport(os)
    import os
#endif

/// The only logging entry point in Vivra.
///
/// Messages are `StaticString`, so a runtime value such as a heart rate, a
/// note or a date can never be interpolated into a log line. The only runtime
/// data a call can attach is an integer count or error code, which is all
/// diagnostics need. CI rejects `print`, `NSLog` and direct `Logger` use
/// elsewhere (see `scripts/check-guards.sh`).
public struct Log: Sendable {
    public let category: String

    #if canImport(os)
        private let logger: Logger
    #endif

    public init(category: String) {
        self.category = category
        #if canImport(os)
            logger = Logger(subsystem: Log.subsystem, category: category)
        #endif
    }

    public static let subsystem = "app.vivra"

    public static let app = Log(category: "app")
    public static let store = Log(category: "store")
    public static let sync = Log(category: "sync")
    public static let insights = Log(category: "insights")
    public static let narrative = Log(category: "narrative")

    /// Records that something happened.
    public func event(_ message: StaticString) {
        #if canImport(os)
            logger.info("\(message.description, privacy: .public)")
        #endif
    }

    /// Records that something happened, with a count (rows written, samples
    /// fetched, retries).
    public func event(_ message: StaticString, count: Int) {
        #if canImport(os)
            logger.info("\(message.description, privacy: .public) count=\(count, privacy: .public)")
        #endif
    }

    /// Records a failure with a numeric code (an `OSStatus`, SQLite result
    /// code or `NSError.code`). Never pass error descriptions: they can
    /// contain file paths or values.
    public func failure(_ message: StaticString, code: Int) {
        #if canImport(os)
            logger.error("\(message.description, privacy: .public) code=\(code, privacy: .public)")
        #endif
    }
}
