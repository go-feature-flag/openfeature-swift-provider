import Foundation

struct GoFeatureFlagProviderOptions {
    let endpoint: String
    var pollInterval: TimeInterval = 30
    var networkService: NetworkingService? = URLSession.shared
}
