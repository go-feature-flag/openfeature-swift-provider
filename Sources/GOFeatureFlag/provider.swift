import Foundation
import OFREP
import OpenFeature
import Combine

struct Metadata: ProviderMetadata {
    var name: String? = "GO Feature Flag provider"
}

public final class GoFeatureFlagProvider: FeatureProvider {
    public var hooks: [any OpenFeature.Hook] = []
    public var metadata: ProviderMetadata = Metadata()
    private let ofrepProvider: OfrepProvider
    private let dataCollectorMngr: DataCollectorManager
    private let options: GoFeatureFlagProviderOptions

    public init(options: GoFeatureFlagProviderOptions) {
        var networkService: NetworkingService = URLSession.shared
        if let netSer = options.networkService {
            networkService = netSer
        }

        var headers: [String:String] = [:]
        if let apiKey = options.apiKey {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        let ofrepOptions = OfrepProviderOptions(
            endpoint: options.endpoint,
            pollInterval: options.pollInterval,
            headers: headers,
            networkService: networkService
        )
        self.options = options
        self.ofrepProvider = OfrepProvider(options: ofrepOptions)
        self.dataCollectorMngr = DataCollectorManager(
            goffAPI: GoFeatureFlagAPI(networkingService: networkService, options: options),
            options: options
        )
    }

    public func initialize(initialContext: (any OpenFeature.EvaluationContext)?) {
        self.hooks = dataCollectorMngr.getHooks()
        self.ofrepProvider.initialize(initialContext: initialContext)

        if self.options.dataCollectorInterval > 0 {
            self.hooks.append(BooleanHook(dataCollectorMngr: self.dataCollectorMngr))
            self.hooks.append(DoubleHook(dataCollectorMngr: self.dataCollectorMngr))
            self.hooks.append(IntegerHook(dataCollectorMngr: self.dataCollectorMngr))
            self.hooks.append(StringHook(dataCollectorMngr: self.dataCollectorMngr))
            self.hooks.append(ObjectHook(dataCollectorMngr: self.dataCollectorMngr))
            self.dataCollectorMngr.start()
        }
    }

    public func onContextSet(
        oldContext: (any OpenFeature.EvaluationContext)?,
        newContext: any OpenFeature.EvaluationContext) {
            self.ofrepProvider.onContextSet(
                oldContext: oldContext,
                newContext: newContext)
        }

    public func getBooleanEvaluation(
        key: String,
        defaultValue: Bool,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<Bool> {
        return try self.ofrepProvider.getBooleanEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context)
    }

    public func getStringEvaluation(
        key: String,
        defaultValue: String,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<String> {
        return try self.ofrepProvider.getStringEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context)
    }

    public func getIntegerEvaluation(
        key: String,
        defaultValue: Int64,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<Int64> {
        return try self.ofrepProvider.getIntegerEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context)
    }

    public func getDoubleEvaluation(
        key: String,
        defaultValue: Double,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<Double> {
        return try self.ofrepProvider.getDoubleEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context)
    }

    public func getObjectEvaluation(
        key: String,
        defaultValue: OpenFeature.Value,
        context: (any OpenFeature.EvaluationContext)?)
    throws -> OpenFeature.ProviderEvaluation<OpenFeature.Value> {
        return try self.ofrepProvider.getObjectEvaluation(
            key: key,
            defaultValue: defaultValue,
            context: context)
    }

    public func observe() -> AnyPublisher<OpenFeature.ProviderEvent, Never> {
        return self.ofrepProvider.observe()
    }
}
