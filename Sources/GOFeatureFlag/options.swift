import Foundation
import OFREP

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

    public init(
        endpoint: String,
        pollInterval: TimeInterval = 60,
        apiKey: String? = nil,
        dataFlushInterval: TimeInterval = 600,
        exporterMetadata: [String:ExporterMetadataValue]? = [:],
        networkService: NetworkingService? = URLSession.shared) {
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.apiKey = apiKey
        self.networkService = networkService
        self.dataCollectorInterval = dataFlushInterval
        self.exporterMetadata = exporterMetadata
    }
}
