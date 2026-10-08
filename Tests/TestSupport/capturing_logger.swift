import Foundation
import OpenFeature

/// Collects the messages it receives, so that a test can assert on what the provider logged, at which
/// level, and on which logger it used.
public struct CapturingLogger: OpenFeatureLogger {
    public enum Level {
        case debug, info, warning, error
    }

    public final class Store {
        private let lock = NSLock()
        private var entries: [(level: Level, message: String)] = []

        public init() {}

        public var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return entries.map { $0.message }
        }

        public func messages(at level: Level) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return entries.filter { $0.level == level }.map { $0.message }
        }

        public func append(_ message: String, at level: Level) {
            lock.lock()
            defer { lock.unlock() }
            entries.append((level, message))
        }
    }

    public let store: Store

    public init(store: Store) {
        self.store = store
    }

    public func debug(_ message: @autoclosure () -> String) {
        store.append(message(), at: .debug)
    }

    public func info(_ message: @autoclosure () -> String) {
        store.append(message(), at: .info)
    }

    public func warning(_ message: @autoclosure () -> String) {
        store.append(message(), at: .warning)
    }

    public func error(_ message: @autoclosure () -> String) {
        store.append(message(), at: .error)
    }
}
