import Foundation

public struct OfrepProviderOptions {
    public let endpoint: String
    public var pollInterval: TimeInterval
    public var headers: [String:String]?
    public var networkService: NetworkingService?

    public init(
        endpoint: String,
        pollInterval: TimeInterval = 30,
        headers: [String:String] = [:],
        networkService: NetworkingService? = URLSession.shared) {
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.headers = headers
        self.networkService = networkService
    }
}
