import Foundation
import Logging

/// Collects the messages it receives, so that a test can assert on what the provider logged.
/// A copy of the one in `OFREPTests`: the two test targets cannot share code.
struct CapturingLogHandler: LogHandler {
    final class Store {
        private let lock = NSLock()
        private var storedMessages: [String] = []

        var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storedMessages
        }

        func append(_ message: String) {
            lock.lock()
            defer { lock.unlock() }
            storedMessages.append(message)
        }
    }

    /// The provider logs some of its diagnostics at the debug level, which the default log level hides.
    static func logger(label: String, store: Store) -> Logger {
        return Logger(label: label) { _ in CapturingLogHandler(store: store) }
    }

    let store: Store
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .debug

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
             source: String, file: String, function: String, line: UInt) {
        store.append("\(message)")
    }
}
