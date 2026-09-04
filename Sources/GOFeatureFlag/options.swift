import Foundation
import OFREP
import Logging

public struct GoFeatureFlagProviderOptions {
    /**
     * (mandatory) endpoint contains the DNS of your GO Feature Flag relay proxy
     * example: https://mydomain.com/gofeatureflagproxy/
     */
    public let endpoint: String
    /**
     * (optional) pollInterval is the time used to check if the configuration has changed in the relay proxy
     * default: 60 seconds
     */
    public var pollInterval: TimeInterval
    /**
     * (optional) If the relay proxy is configured to authenticate the requests, you should provide
     * an API Key to the provider.
     * Please ask the administrator of the relay proxy to provide an API Key.
     * (This feature is available only if you are using GO Feature Flag relay proxy v1.7.0 or above)
     * Default: null
     */
    public var apiKey: String?
    /**
     * (optional) custom headers to be sent for every HTTP request.
     * default: empty
     */
    public var customHeaders: [String:String]? = [:]
    /**
     * (optional) interval time we publish statistics collection data to the proxy.
     * The parameter is used only if the cache is enabled, otherwise the collection of the data is done directly
     * when calling the evaluation API.
     * default: 600 seconds
     */
    public let dataCollectorInterval: TimeInterval
    /**
     * (optional) network interface used to perform the HTTP call
     * default: URLSession.shared
     */
    public var networkService: NetworkingService?
    /**
     * (optional) exporter metadata to be sent to the relay proxy data collector to be used for evaluation data events.
     * default: empty
     */
    public var exporterMetadata: [String:ExporterMetadataValue]? = [:]
    /**
     * (optional) logger used by the provider for its own diagnostics.
     * The logger passed by the OpenFeature SDK during a flag evaluation takes precedence,
     * except in the data collection hooks, which the SDK gives no logger to.
     * default: Logger(label: "org.gofeatureflag.provider")
     */
    public var logger: Logger?

    public init(
        endpoint: String,
        pollInterval: TimeInterval = 60,
        apiKey: String? = nil,
        customHeaders: [String:String]? = [:],
        dataFlushInterval: TimeInterval = 600,
        exporterMetadata: [String:ExporterMetadataValue]? = [:],
        networkService: NetworkingService? = URLSession.shared,
        logger: Logger? = nil) {
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.networkService = networkService
        self.dataCollectorInterval = dataFlushInterval
        self.exporterMetadata = exporterMetadata
        self.logger = logger
    }
}
