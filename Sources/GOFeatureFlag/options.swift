import Foundation
import OFREP

public struct GoFeatureFlagProviderOptions {
    public let endpoint: String
    public var pollInterval: TimeInterval
    public var networkService: NetworkingService?
    public var apiKey: String?

    public init(
        endpoint: String,
        pollInterval: TimeInterval = 30,
        apiKey: String?,
        networkService: NetworkingService? = URLSession.shared) {
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.apiKey = apiKey
        self.networkService = networkService
    }
}
