import Foundation
import OFREP
import OpenFeature
import Combine
import Logging

struct Metadata: ProviderMetadata {
    var name: String? = "GO Feature Flag provider"
}

public final class GoFeatureFlagProvider: FeatureProvider {
    public var hooks: [any OpenFeature.Hook] = []
    public var metadata: ProviderMetadata = Metadata()
    private let ofrepProvider: OfrepProvider
    private let dataCollectorMngr: DataCollectorManager
    private let options: GoFeatureFlagProviderOptions
    private let logger: Logger

    public init(options: GoFeatureFlagProviderOptions) {
        var networkService: NetworkingService = URLSession.shared
        if let netSer = options.networkService {
            networkService = netSer
        }

        var headers: [String:String] = options.customHeaders ?? [:]
        if let apiKey = options.apiKey {
            // Authorization is the legacy header used for authentication against the relayproxy
            // We are now using X-API-Key as the main header to forward API Keys.
            // We keep Authorization only for background compatibility.
            headers["Authorization"] = "Bearer \(apiKey)"
            headers["X-API-Key"] = apiKey
        }
        let logger = options.logger ?? Logger(label: "org.gofeatureflag.provider")
        let ofrepOptions = OfrepProviderOptions(
            endpoint: options.endpoint,
            pollInterval: options.pollInterval,
            headers: headers,
            networkService: networkService,
            logger: logger
        )
        self.options = options
        self.logger = logger
        self.ofrepProvider = OfrepProvider(options: ofrepOptions)
        self.dataCollectorMngr = DataCollectorManager(
            goffAPI: GoFeatureFlagAPI(networkingService: networkService, options: options),
            options: options,
            logger: logger
        )
    }

    /// The provider delegates all its evaluations to OFREP, so it also delegates its status.
    public var status: ProviderStatus {
        return self.ofrepProvider.status
    }

    public func initialize(initialContext: OpenFeature.EvaluationContext?) -> Future<Void, Never> {
        self.hooks = self.dataCollectorMngr.getHooks()
        return Future { promise in
            var cancellable: AnyCancellable?
            cancellable = self.ofrepProvider.initialize(initialContext: initialContext)
                .sink { _ in
                    withExtendedLifetime(cancellable) {}
                    if self.options.dataCollectorInterval > 0 {
                        self.hooks.append(
                            BooleanHook(dataCollectorMngr: self.dataCollectorMngr, logger: self.logger))
                        self.hooks.append(
                            DoubleHook(dataCollectorMngr: self.dataCollectorMngr, logger: self.logger))
                        self.hooks.append(
                            IntegerHook(dataCollectorMngr: self.dataCollectorMngr, logger: self.logger))
                        self.hooks.append(
                            StringHook(dataCollectorMngr: self.dataCollectorMngr, logger: self.logger))
                        self.hooks.append(
                            ObjectHook(dataCollectorMngr: self.dataCollectorMngr, logger: self.logger))
                        self.dataCollectorMngr.start()
                    }
                    promise(.success(()))
                }
        }
    }

    public func onContextSet(
        oldContext: (any OpenFeature.EvaluationContext)?,
        newContext: any OpenFeature.EvaluationContext) -> Future<Void, Never> {
            return self.ofrepProvider.onContextSet(
                oldContext: oldContext,
                newContext: newContext)
        }

    public func getBooleanEvaluation(
        key: String,
        defaultValue: Bool,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<Bool> {
        return try self.getBooleanEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: nil)
    }

    public func getBooleanEvaluation(
        key: String,
        defaultValue: Bool,
        context: (any OpenFeature.EvaluationContext)?,
        logger: Logger?)
    throws -> OpenFeature.ProviderEvaluation<Bool> {
        return try self.ofrepProvider.getBooleanEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: logger)
    }

    public func getStringEvaluation(
        key: String,
        defaultValue: String,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<String> {
        return try self.getStringEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: nil)
    }

    public func getStringEvaluation(
        key: String,
        defaultValue: String,
        context: (any OpenFeature.EvaluationContext)?,
        logger: Logger?)
    throws -> OpenFeature.ProviderEvaluation<String> {
        return try self.ofrepProvider.getStringEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: logger)
    }

    public func getIntegerEvaluation(
        key: String,
        defaultValue: Int64,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<Int64> {
        return try self.getIntegerEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: nil)
    }

    public func getIntegerEvaluation(
        key: String,
        defaultValue: Int64,
        context: (any OpenFeature.EvaluationContext)?,
        logger: Logger?)
    throws -> OpenFeature.ProviderEvaluation<Int64> {
        return try self.ofrepProvider.getIntegerEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: logger)
    }

    public func getDoubleEvaluation(
        key: String,
        defaultValue: Double,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<Double> {
        return try self.getDoubleEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: nil)
    }

    public func getDoubleEvaluation(
        key: String,
        defaultValue: Double,
        context: (any OpenFeature.EvaluationContext)?,
        logger: Logger?)
    throws -> OpenFeature.ProviderEvaluation<Double> {
        return try self.ofrepProvider.getDoubleEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: logger)
    }

    public func getObjectEvaluation(
        key: String,
        defaultValue: OpenFeature.Value,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<OpenFeature.Value> {
        return try self.getObjectEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: nil)
    }

    public func getObjectEvaluation(
        key: String,
        defaultValue: OpenFeature.Value,
        context: (any OpenFeature.EvaluationContext)?,
        logger: Logger?)
    throws -> OpenFeature.ProviderEvaluation<OpenFeature.Value> {
        return try self.ofrepProvider.getObjectEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context,
            logger: logger)
    }

    public func observe() -> AnyPublisher<OpenFeature.ProviderEvent, Never> {
        return self.ofrepProvider.observe()
    }
}
