import Foundation

public struct GoFeatureFlagProviderOptions {
    public let endpoint: String
    public var pollInterval: TimeInterval
    public var networkService: NetworkingService?

    public init(
        endpoint: String,
        pollInterval: TimeInterval = 30,
        networkService: NetworkingService? = URLSession.shared) {
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.networkService = networkService
    }
}
