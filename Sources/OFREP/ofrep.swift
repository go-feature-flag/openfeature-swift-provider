import OpenFeature
import Foundation
import Combine
import Logging

struct Metadata: ProviderMetadata {
    var name: String? = "OFREP provider"
}

public class OfrepProvider: FeatureProvider {
    private let statusTracker = ProviderStatusTracker()
    private var evaluationContext: OpenFeature.EvaluationContext?

    private var options: OfrepProviderOptions
    private let ofrepAPI: OfrepAPI

    private var inMemoryCache: [String: OfrepEvaluationResponseFlag] = [:]
    private var apiRetryAfter: Date?
    private var timer: DispatchSourceTimer?
    /// The reconciliation started by the latest `onContextSet`, kept so that a newer
    /// context change can cancel it before starting its own.
    private var reconcileTask: Task<Void, Never>?

    /// The initial evaluation started by `initialize`, kept so that a context change arriving before
    /// it finishes can cancel it — otherwise its response could land last and overwrite the new
    /// context's flags while the provider reports ready for the new context.
    private var initTask: Task<Void, Never>?

    /// Serializes access to the mutable state shared between the synchronous evaluation calls
    /// (`getXxxEvaluation`, invoked on the caller's thread) and the background work that refreshes it
    /// (the `initialize`/`onContextSet` Tasks and the polling timer, which run on unrelated threads).
    /// `NSLock.withLock` requires macOS 13+, so we keep a small helper to preserve the macOS 12 floor.
    private let stateLock = NSLock()

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return try body()
    }

    public init(options: OfrepProviderOptions) {
        self.options = options
        var networkService: NetworkingService = URLSession.shared
        if let netSer = self.options.networkService {
            networkService = netSer
        }
        self.ofrepAPI = OfrepAPI(networkingService: networkService, options: self.options)
    }

    /// Stops the background polling and cancels any in-flight lifecycle work. The 0.6.0 SDK exposes
    /// no teardown hook, so without this a resumed `DispatchSourceTimer` keeps polling the API until
    /// the provider is deallocated. Call it when the provider is no longer used; it is idempotent and
    /// is also invoked from `deinit`.
    public func shutdown() {
        self.stopBackgroundWork()
    }

    deinit {
        // `deinit` calls a private helper rather than the overridable `shutdown()`.
        self.stopBackgroundWork()
    }

    private func stopBackgroundWork() {
        self.timer?.cancel()
        self.timer = nil
        self.reconcileTask?.cancel()
        self.reconcileTask = nil
        self.initTask?.cancel()
        self.initTask = nil
    }

    public var hooks: [any Hook] = []
    public var metadata: ProviderMetadata = Metadata()

    /// The current lifecycle status of the provider.
    /// `ProviderStatusTracker` keeps this in sync with the events we emit below.
    public var status: ProviderStatus {
        return self.statusTracker.status
    }

    public func observe() -> AnyPublisher<OpenFeature.ProviderEvent, Never> {
        return self.statusTracker.observe()
    }

    public func initialize(initialContext: (any OpenFeature.EvaluationContext)?) -> Future<Void, Never> {
        self.withStateLock { self.evaluationContext = initialContext }
        return Future { promise in
            self.initTask = Task {
                do {
                    let status = try await self.evaluateFlags(context: initialContext)
                    guard status == .successWithChanges else {
                        throw OpenFeatureError.generalError(
                            message: "impossible to initialize the provider, receive unknown status")
                    }
                    self.statusTracker.send(.ready(nil))
                } catch is CancellationError {
                    // A context change arrived before initialize finished and superseded it; that
                    // context change owns the terminal event, so this initialize must stay silent.
                } catch {
                    self.statusTracker.send(OfrepProvider.errorEvent(from: error))
                }
                // Start polling regardless of how the initial fetch went. A transient failure on the
                // first call (a network blip, a 5xx, a first-call 429) must not permanently disable
                // polling, otherwise the provider would stay in error forever with an empty cache and
                // no way to retry — the poll below is what heals it back to `.ready`.
                if self.options.pollInterval > 0 {
                    self.startPolling(pollInterval: self.options.pollInterval)
                }
                // The event is always emitted before resolving, so that callers of
                // setProviderAndWait observe the correct status as soon as it returns.
                promise(.success(()))
            }
        }
    }

    public func onContextSet(oldContext: (any OpenFeature.EvaluationContext)?,
                             newContext: any OpenFeature.EvaluationContext) -> Future<Void, Never> {
        // Since 0.6.0 the SDK no longer waits for the returned Future to resolve before
        // dispatching the next lifecycle call, so another context change can arrive while this
        // one is still in flight. Drop the superseded work: without this its response could
        // land last and leave the cache holding the flags of the context we just left.
        self.reconcileTask?.cancel()
        // Also supersede an initialize still in flight: without this, its response could land last
        // and overwrite the cache with the previous context's flags while we report ready here.
        self.initTask?.cancel()
        self.withStateLock { self.evaluationContext = newContext }
        self.statusTracker.send(.reconciling(nil))
        return Future { promise in
            self.reconcileTask = Task {
                do {
                    let status = try await self.evaluateFlags(context: newContext)
                    // Cancel may land after evaluateFlags returns (including 304 / rateLimited
                    // paths that never hit the cache-write guard). Stay silent: the superseding
                    // call owns the terminal event.
                    try Task.checkCancellation()
                    if status == .rateLimited {
                        // We never reached the API, so the cache still holds the flags of the
                        // previous context: `.contextChanged` would wrongly report `.ready`.
                        self.statusTracker.send(.stale(nil))
                    } else {
                        self.statusTracker.send(.contextChanged(nil))
                    }
                } catch is CancellationError {
                    // A newer context change superseded this one and emits its own terminal
                    // event, so this one has to stay silent.
                } catch let error as OfrepError {
                    // Same rule as above: a cancelled reconcile must not emit or mutate status.
                    guard !Task.isCancelled else {
                        promise(.success(()))
                        return
                    }
                    switch error {
                    case .apiTooManyRequestsError:
                        // we want to stay stale in that case, so we report it as such
                        // instead of surfacing an error.
                        self.statusTracker.send(.stale(nil))
                    default:
                        self.statusTracker.send(OfrepProvider.errorEvent(from: error))
                    }
                } catch {
                    guard !Task.isCancelled else {
                        promise(.success(()))
                        return
                    }
                    self.statusTracker.send(OfrepProvider.errorEvent(from: error))
                }
                // On the winning (non-cancelled) path a terminal event is always emitted,
                // otherwise the status would stay stuck on `.reconciling`.
                promise(.success(()))
            }
        }
    }

    /// Converts an error raised during a lifecycle operation into the event the SDK
    /// used to derive from a thrown error before 0.6.0.
    private static func errorEvent(from error: Error) -> ProviderEvent {
        switch error {
        case OfrepError.apiUnauthorizedError, OfrepError.forbiddenError:
            return .error(ProviderEventDetails(message: error.localizedDescription, errorCode: .providerFatal))
        case let openFeatureError as OpenFeatureError:
            // `localizedDescription` is useless for this enum, `description` carries the message.
            return .error(
                ProviderEventDetails(
                    message: openFeatureError.description,
                    errorCode: openFeatureError.errorCode()))
        default:
            return .error(ProviderEventDetails(message: error.localizedDescription))
        }
    }

    /// Maps the error carried by a bulk evaluation response to the matching OpenFeature error.
    private static func openFeatureError(from response: OfrepEvaluationResponse) -> OpenFeatureError {
        switch response.errorCode {
        case .providerNotReady:
            return OpenFeatureError.providerNotReadyError
        case .parseError:
            return OpenFeatureError.parseError(message: response.errorDetails ?? "impossible to parse")
        case .targetingKeyMissing:
            return OpenFeatureError.targetingKeyMissingError
        case .invalidContext:
            return OpenFeatureError.invalidContextError
        default:
            return OpenFeatureError.generalError(message: response.errorDetails ?? "")
        }
    }

    /// Indexes the flags of a bulk evaluation response by key, keeping the last one for a
    /// duplicated key. Flags without a key are not addressable and are dropped.
    private static func cache(
        from flags: [OfrepEvaluationResponseFlag]
    ) -> [String: OfrepEvaluationResponseFlag] {
        return Dictionary(
            flags.compactMap { flag in flag.key.map { ($0, flag) } },
            uniquingKeysWith: { _, latest in latest })
    }

    /// True while the `Retry-After` window installed by a previous 429 is still open.
    private var isWithinRetryWindow: Bool {
        return self.withStateLock {
            guard let retryAfter = self.apiRetryAfter else {
                return false
            }
            return retryAfter > Date()
        }
    }

    private func evaluateFlags(context: EvaluationContext?) async throws -> BulkEvaluationStatus {
        if self.isWithinRetryWindow {
            // we don't want to call the API because we got a 429
            try Task.checkCancellation()
            return BulkEvaluationStatus.rateLimited
        }

        let ofrepEvalResponse: OfrepEvaluationResponse
        let httpResp: HTTPURLResponse
        do {
            (ofrepEvalResponse, httpResp) = try await self.ofrepAPI.postBulkEvaluateFlags(context: context)
        } catch let error as OfrepError {
            // A superseded reconcile must not install a retry window that would make the
            // winning call return `.rateLimited` with the wrong context's flags.
            try Task.checkCancellation()
            if case .apiTooManyRequestsError(let response) = error {
                let retryAfter = self.getRetryAfterDate(from: response)
                self.withStateLock { self.apiRetryAfter = retryAfter }
            }
            throw error
        }

        // Apply the cancellation policy before any return or mutation, including 304 /
        // error bodies that never reach the cache-write guard below.
        try Task.checkCancellation()

        if httpResp.statusCode == 304 {
            return BulkEvaluationStatus.successNoChanges
        }

        if ofrepEvalResponse.isError() {
            throw OfrepProvider.openFeatureError(from: ofrepEvalResponse)
        }

        let refreshedCache = OfrepProvider.cache(from: ofrepEvalResponse.flags)
        // The response of a reconciliation that `onContextSet` has cancelled must not
        // overwrite the cache filled by the context change that replaced it.
        try Task.checkCancellation()
        self.withStateLock { self.inMemoryCache = refreshedCache }
        return BulkEvaluationStatus.successWithChanges
    }

    private func getRetryAfterDate(from response: HTTPURLResponse) -> Date? {
        // HTTP header names are case-insensitive; `value(forHTTPHeaderField:)` looks them up
        // case-insensitively, unlike subscripting `allHeaderFields`, so a lowercase `retry-after`
        // (common over HTTP/2) is still honoured.
        guard let retryAfterValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        // Try to parse Retry-After as an interval in seconds
        if let retryAfterInterval = TimeInterval(retryAfterValue) {
            return Date().addingTimeInterval(retryAfterInterval)
        }

        // Try to parse Retry-After as an HTTP-date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"  // Common HTTP-date format
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        return dateFormatter.date(from: retryAfterValue)
    }

    private func startPolling(pollInterval: TimeInterval) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer?.schedule(deadline: .now(), repeating: pollInterval, leeway: .milliseconds(100))
        timer?.setEventHandler { [weak self] in
            guard let weakSelf = self else { return }
            Task {
                do {
                    let status = try await weakSelf.evaluateFlags(
                        context: weakSelf.withStateLock { weakSelf.evaluationContext })
                    if status != .rateLimited && (weakSelf.status == .stale || weakSelf.status == .error) {
                        // We reached the API again, so the cache is up to date. `.ready` has to
                        // be emitted explicitly: the tracker maps `.configurationChanged` to no
                        // status change, which would otherwise leave the provider stuck in `.stale`
                        // or `.error`. `.fatal` is intentionally not recovered: it is terminal.
                        weakSelf.statusTracker.send(.ready(nil))
                    }
                    if status == .successWithChanges {
                        weakSelf.statusTracker.send(.configurationChanged())
                    }
                } catch let error as OfrepError {
                    switch error {
                    case .apiTooManyRequestsError:
                        weakSelf.statusTracker.send(.stale())
                    default:
                        providerLogger.error("error while polling the OFREP API: \(error)")
                    }
                } catch {
                    providerLogger.error("error while polling the OFREP API: \(error)")
                }
            }
        }

        timer?.resume()
    }
}

/// Flag resolution, kept apart from the lifecycle of the provider above.
extension OfrepProvider {
    public func getBooleanEvaluation(key: String, defaultValue: Bool,
                                     context: EvaluationContext?) throws -> ProviderEvaluation<Bool> {
        return try self.getBooleanEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getBooleanEvaluation(key: String, defaultValue: Bool, context: EvaluationContext?,
                                     logger: Logger?) throws -> ProviderEvaluation<Bool> {
        let flagCached = try self.genericEvaluation(key: key, logger: logger)
        guard let value = flagCached.value?.asBoolean() else {
            self.resolveLogger(logger).debug("flag \(key) is not a boolean")
            throw OpenFeatureError.typeMismatchError
        }
        return ProviderEvaluation<Bool>(
            value: value,
            flagMetadata: flagCached.flagMetadata ?? [:],
            variant: flagCached.variant,
            reason: flagCached.reason)
    }

    public func getStringEvaluation(key: String, defaultValue: String,
                                    context: EvaluationContext?) throws -> ProviderEvaluation<String> {
        return try self.getStringEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getStringEvaluation(key: String, defaultValue: String, context: EvaluationContext?,
                                    logger: Logger?) throws -> ProviderEvaluation<String> {
        let flagCached = try self.genericEvaluation(key: key, logger: logger)
        guard let value = flagCached.value?.asString() else {
            self.resolveLogger(logger).debug("flag \(key) is not a string")
            throw OpenFeatureError.typeMismatchError
        }
        return ProviderEvaluation<String>(
            value: value,
            flagMetadata: flagCached.flagMetadata ?? [:],
            variant: flagCached.variant,
            reason: flagCached.reason)
    }

    public func getIntegerEvaluation(key: String, defaultValue: Int64,
                                     context: EvaluationContext?) throws -> ProviderEvaluation<Int64> {
        return try self.getIntegerEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getIntegerEvaluation(key: String, defaultValue: Int64, context: EvaluationContext?,
                                     logger: Logger?) throws -> ProviderEvaluation<Int64> {
        let flagCached = try self.genericEvaluation(key: key, logger: logger)
        guard let value = flagCached.value?.asInteger() else {
            self.resolveLogger(logger).debug("flag \(key) is not an integer")
            throw OpenFeatureError.typeMismatchError
        }
        return ProviderEvaluation<Int64>(
            value: Int64(value),
            flagMetadata: flagCached.flagMetadata ?? [:],
            variant: flagCached.variant,
            reason: flagCached.reason)
    }

    public func getDoubleEvaluation(key: String, defaultValue: Double,
                                    context: EvaluationContext?) throws -> ProviderEvaluation<Double> {
        return try self.getDoubleEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getDoubleEvaluation(key: String, defaultValue: Double, context: EvaluationContext?,
                                    logger: Logger?) throws -> ProviderEvaluation<Double> {
        let flagCached = try self.genericEvaluation(key: key, logger: logger)
        guard let value = flagCached.value?.asDouble() else {
            self.resolveLogger(logger).debug("flag \(key) is not a double")
            throw OpenFeatureError.typeMismatchError
        }
        return ProviderEvaluation<Double>(
            value: value,
            flagMetadata: flagCached.flagMetadata ?? [:],
            variant: flagCached.variant,
            reason: flagCached.reason)

    }

    public func getObjectEvaluation(key: String, defaultValue: Value,
                                    context: EvaluationContext?) throws -> ProviderEvaluation<Value> {
        return try self.getObjectEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getObjectEvaluation(key: String, defaultValue: Value, context: EvaluationContext?,
                                    logger: Logger?) throws -> ProviderEvaluation<Value> {
        let flagCached = try self.genericEvaluation(key: key, logger: logger)
        let objValue = flagCached.value?.asObject()
        let arrayValue = flagCached.value?.asArray()

        if objValue == nil && arrayValue == nil {
            self.resolveLogger(logger).debug("flag \(key) is neither an object nor a list")
            throw OpenFeatureError.typeMismatchError
        }

        if objValue != nil {
            var convertedValue: [String:Value] = [:]
            objValue?.forEach { key, value in
                convertedValue[key]=value.toValue()
            }

            return ProviderEvaluation<Value>(
                value: Value.structure(convertedValue),
                flagMetadata: flagCached.flagMetadata ?? [:],
                variant: flagCached.variant,
                reason: flagCached.reason)
        }

        if arrayValue != nil {
            var convertedValue: [Value] = []
            arrayValue?.forEach { item in
                convertedValue.append(item.toValue())
            }
            return ProviderEvaluation<Value>(
                value: Value.list(convertedValue),
                flagMetadata: flagCached.flagMetadata ?? [:],
                variant: flagCached.variant,
                reason: flagCached.reason
            )
        }
        throw OpenFeatureError.generalError(
            message: "impossible to evaluate the flag because it is not a list or a dictionnary")
    }

    /// Returns the logger provided by the SDK for this evaluation, falling back to the one the
    /// SDK was configured with globally.
    private func resolveLogger(_ logger: Logger?) -> Logger {
        return logger ?? providerLogger
    }

    private func genericEvaluation(key: String, logger: Logger?) throws -> OfrepEvaluationResponseFlag {
        guard let flagCached = self.withStateLock({ self.inMemoryCache[key] }) else {
            self.resolveLogger(logger).debug("no flag found in cache for the key \(key)")
            throw OpenFeatureError.flagNotFoundError(key: key)
        }

        if flagCached.isError() {
            self.resolveLogger(logger).debug(
                "error while evaluating the flag \(key): \(flagCached.errorDetails ?? "no details")")
            switch flagCached.errorCode {
            case .flagNotFound:
                throw OpenFeatureError.flagNotFoundError(key: key)
            case .invalidContext:
                throw OpenFeatureError.invalidContextError
            case .parseError:
                throw OpenFeatureError.parseError(message: flagCached.errorDetails ?? "parse error")
            case .providerNotReady:
                throw OpenFeatureError.providerNotReadyError
            case .targetingKeyMissing:
                throw OpenFeatureError.targetingKeyMissingError
            case .typeMismatch:
                throw OpenFeatureError.typeMismatchError
            default:
                throw OpenFeatureError.generalError(message: flagCached.errorDetails ?? "general error")
            }
        }
        return flagCached
    }
}
