import OpenFeature
import Foundation
import Combine

struct Metadata: ProviderMetadata {
    var name: String? = "OFREP provider"
}

public class OfrepProvider: FeatureProvider {
    private let eventHandler = EventHandler()
    private var evaluationContext: OpenFeature.EvaluationContext?

    private var options: OfrepProviderOptions
    private let ofrepAPI: OfrepAPI

    private var inMemoryCache: [String: OfrepEvaluationResponseFlag] = [:]
    private var apiRetryAfter: Date?
    private var timer: DispatchSourceTimer?

    public init(options: OfrepProviderOptions) {
        self.options = options
        var networkService: NetworkingService = URLSession.shared
        if let netSer = self.options.networkService {
            networkService = netSer
        }
        self.ofrepAPI = OfrepAPI(networkingService: networkService, options: self.options)
    }

    public var hooks: [any Hook] = []
    public var metadata: ProviderMetadata = Metadata()

    public func observe() -> AnyPublisher<OpenFeature.ProviderEvent?, Never> {
            return eventHandler.observe()
    }
    
    public func initialize(initialContext: (any OpenFeature.EvaluationContext)?) async throws {
        self.evaluationContext = initialContext
        do {
            let status = try await self.evaluateFlags(context: self.evaluationContext)
            if self.options.pollInterval > 0 {
                self.startPolling(pollInterval: self.options.pollInterval)
            }

            if status == .successWithChanges {
                return
            }
            
            throw OpenFeatureError.generalError(message: "impossible to initialize the provider, receive unknown status")
        } catch {
            switch error {
            case OfrepError.apiUnauthorizedError, OfrepError.forbiddenError:
                throw OpenFeatureError.providerFatalError(message: error.localizedDescription)
            default:
                throw error
            }
        }
    }

    public func onContextSet(oldContext: (any OpenFeature.EvaluationContext)?,
                             newContext: any OpenFeature.EvaluationContext) async throws {
        self.evaluationContext = newContext
        do {
            let status = try await self.evaluateFlags(context: newContext)
            if(status == .successWithChanges || status == .successNoChanges ) {
                return
            }
        } catch let error as OfrepError {
            switch error {
            case .apiTooManyRequestsError:
                return // we want to stay stale in that case so we ignore the error.
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    public func getBooleanEvaluation(key: String, defaultValue: Bool,
                                     context: EvaluationContext?) throws -> ProviderEvaluation<Bool> {
        let flagCached = try genericEvaluation(key: key)
        guard let value = flagCached.value?.asBoolean() else {
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
        let flagCached = try genericEvaluation(key: key)
        guard let value = flagCached.value?.asString() else {
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
        let flagCached = try genericEvaluation(key: key)
        guard let value = flagCached.value?.asInteger() else {
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
        let flagCached = try genericEvaluation(key: key)
        guard let value = flagCached.value?.asDouble() else {
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
        let flagCached = try genericEvaluation(key: key)
        let objValue = flagCached.value?.asObject()
        let arrayValue = flagCached.value?.asArray()

        if objValue == nil && arrayValue == nil {
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

    private func genericEvaluation(key: String) throws -> OfrepEvaluationResponseFlag {
        guard let flagCached = self.inMemoryCache[key] else {
            throw OpenFeatureError.flagNotFoundError(key: key)
        }

        if flagCached.isError() {
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

    // swiftlint:disable:next cyclomatic_complexity
    private func evaluateFlags(context: EvaluationContext?) async throws -> BulkEvaluationStatus {
        if self.apiRetryAfter != nil && self.apiRetryAfter! > Date() {
            // we don't want to call the API because we got a 429
            return BulkEvaluationStatus.rateLimited
        }

        do {
            let (ofrepEvalResponse, httpResp) = try await self.ofrepAPI.postBulkEvaluateFlags(context: context)

            if httpResp.statusCode == 304 {
                return BulkEvaluationStatus.successNoChanges
            }

            if ofrepEvalResponse.isError() {
                switch ofrepEvalResponse.errorCode {
                case .providerNotReady:
                    throw OpenFeatureError.providerNotReadyError
                case .parseError:
                    throw OpenFeatureError.parseError(message: ofrepEvalResponse.errorDetails ?? "impossible to parse")
                case .targetingKeyMissing:
                    throw OpenFeatureError.targetingKeyMissingError
                case .invalidContext:
                    throw OpenFeatureError.invalidContextError
                default:
                    throw OpenFeatureError.generalError(message: ofrepEvalResponse.errorDetails ?? "")
                }
            }

            var inMemoryCacheNew: [String:OfrepEvaluationResponseFlag] = [:]
            for flag in ofrepEvalResponse.flags {
                if let key = flag.key {
                    inMemoryCacheNew[key] = flag
                }
            }
            self.inMemoryCache = inMemoryCacheNew
            return BulkEvaluationStatus.successWithChanges
        } catch let error as OfrepError {
            switch error {
            case .apiTooManyRequestsError(let response):
                self.apiRetryAfter = getRetryAfterDate(from: response.allHeaderFields)
                throw error
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    private func getRetryAfterDate(from headers: [AnyHashable: Any]) -> Date? {
        // Retrieve the Retry-After value from headers
        guard let retryAfterValue = headers["Retry-After"] as? String else {
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
                    let status = try await weakSelf.evaluateFlags(context: weakSelf.evaluationContext)
                    if status == .successWithChanges {
                        weakSelf.eventHandler.send(.configurationChanged)
                    }
                } catch let error as OfrepError {
                    switch error {
                    case .apiTooManyRequestsError:
                        weakSelf.eventHandler.send(.stale)
                        throw error
                    default:
                        throw error
                    }
                } catch {
                    throw error
                }
            }
        }

        timer?.resume()
    }
}
