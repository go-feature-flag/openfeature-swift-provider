import Foundation
import Logging

public struct OfrepProviderOptions {
    public let endpoint: String
    public var pollInterval: TimeInterval
    public var headers: [String:String]?
    public var networkService: NetworkingService?
    /**
     * (optional) logger used by the provider for its own diagnostics.
     * The logger passed by the OpenFeature SDK during a flag resolution takes precedence.
     * default: Logger(label: "dev.openfeature.ofrep")
     */
    public var logger: Logger?

    public init(
        endpoint: String,
        pollInterval: TimeInterval = 30,
        headers: [String:String] = [:],
        networkService: NetworkingService? = URLSession.shared,
        logger: Logger? = nil) {
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.headers = headers
        self.networkService = networkService
        self.logger = logger
    }
}
