import Foundation
import OpenFeature

/// Thread-safe storage for the events collected by a Combine subscription.
///
/// The `sink` closure runs on whichever queue the publisher emits on, while the assertions read the
/// events back from the test thread, and the provider keeps publishing while they do. A plain local
/// `var` captured by the closure is therefore a data race, which ThreadSanitizer reports as a
/// "Swift access race" on the captured box.
public final class ReceivedEvents {
    private let lock = NSLock()
    private var storage: [ProviderEvent] = []

    public init() {}

    /// A snapshot of the events received so far.
    public var all: [ProviderEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public var count: Int { return self.all.count }
    public var first: ProviderEvent? { return self.all.first }
    public var last: ProviderEvent? { return self.all.last }

    public func prefix(_ maxLength: Int) -> [ProviderEvent] {
        return Array(self.all.prefix(maxLength))
    }

    /// Records an event and returns how many have been received, so that a subscriber can fulfill an
    /// expectation on a given count without reading it back in a second, unsynchronised step.
    @discardableResult
    public func append(_ event: ProviderEvent) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
        return storage.count
    }
}
