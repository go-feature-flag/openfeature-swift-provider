import Foundation
import Logging

/// Collects the messages it receives, so that a test can assert on what the provider logged and on
/// which logger it used.
public struct CapturingLogHandler: LogHandler {
    public final class Store {
        private let lock = NSLock()
        private var storedMessages: [String] = []

        public init() {}

        public var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storedMessages
        }

        public func append(_ message: String) {
            lock.lock()
            defer { lock.unlock() }
            storedMessages.append(message)
        }
    }

    /// The provider logs some of its diagnostics at the debug level, which the default log level hides.
    public static func logger(label: String, store: Store) -> Logger {
        return Logger(label: label) { _ in CapturingLogHandler(store: store) }
    }

    public let store: Store
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .debug

    public init(store: Store) {
        self.store = store
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
                    source: String, file: String, function: String, line: UInt) {
        store.append("\(message)")
    }
}
