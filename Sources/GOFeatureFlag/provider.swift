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

    public init(options: GoFeatureFlagProviderOptions){
        var headers: [String:String] = [:]
        if let apiKey = options.apiKey {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        let ofrepOptions = OfrepProviderOptions(
            endpoint: options.endpoint,
            pollInterval: options.pollInterval,
            headers: headers,
            networkService: options.networkService
        )
        self.ofrepProvider = OfrepProvider(options: ofrepOptions)
    }

    public func initialize(initialContext: (any OpenFeature.EvaluationContext)?) {
        self.ofrepProvider.initialize(initialContext: initialContext)
    }
    
    public func onContextSet(oldContext: (any OpenFeature.EvaluationContext)?, newContext: any OpenFeature.EvaluationContext) {
        self.ofrepProvider.onContextSet(oldContext: oldContext, newContext: newContext)
    }
    
    public func getBooleanEvaluation(key: String, defaultValue: Bool, context: (any OpenFeature.EvaluationContext)?) throws -> OpenFeature.ProviderEvaluation<Bool> {
        return try self.ofrepProvider.getBooleanEvaluation(key: key, defaultValue: defaultValue, context: context)
    }
    
    public func getStringEvaluation(key: String, defaultValue: String, context: (any OpenFeature.EvaluationContext)?) throws -> OpenFeature.ProviderEvaluation<String> {
        return try self.ofrepProvider.getStringEvaluation(key: key, defaultValue: defaultValue, context: context)
    }
    
    public func getIntegerEvaluation(key: String, defaultValue: Int64, context: (any OpenFeature.EvaluationContext)?) throws -> OpenFeature.ProviderEvaluation<Int64> {
        return try self.ofrepProvider.getIntegerEvaluation(key: key, defaultValue: defaultValue, context: context)
    }
    
    public func getDoubleEvaluation(key: String, defaultValue: Double, context: (any OpenFeature.EvaluationContext)?) throws -> OpenFeature.ProviderEvaluation<Double> {
        return try self.ofrepProvider.getDoubleEvaluation(key: key, defaultValue: defaultValue, context: context)
    }
    
    public func getObjectEvaluation(key: String, defaultValue: OpenFeature.Value, context: (any OpenFeature.EvaluationContext)?) throws -> OpenFeature.ProviderEvaluation<OpenFeature.Value> {
        return try self.ofrepProvider.getObjectEvaluation(key: key, defaultValue: defaultValue, context: context)
    }
    
    public func observe() -> AnyPublisher<OpenFeature.ProviderEvent, Never> {
        return self.ofrepProvider.observe()
    }
}
