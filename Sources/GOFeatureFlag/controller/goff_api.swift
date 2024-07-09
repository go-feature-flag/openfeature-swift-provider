import Foundation
import OpenFeature
import OFREP

class GoFeatureFlagAPI {
    private let networkingService: NetworkingService
    private let options: GoFeatureFlagProviderOptions
    private let metadata: [String:String] = ["provider": "openfeature-swift"]

    init(networkingService: NetworkingService, options: GoFeatureFlagProviderOptions) {
        self.networkingService = networkingService
        self.options = options
    }

    func postDataCollector(events: [FeatureEvent]?) async throws -> (DataCollectorResponse, HTTPURLResponse) {
        guard let events = events else {
            throw GoFeatureFlagError.noEventToSend
        }
        if events.isEmpty {
            throw GoFeatureFlagError.noEventToSend
        }

        guard let url = URL(string: options.endpoint) else {
            throw InvalidOptions.invalidEndpoint(message: "endpoint [" + options.endpoint + "] is not valid")
        }

        let dataCollectorURL = url.appendingPathComponent("v1/data/collector")
        var request = URLRequest(url: dataCollectorURL)
        request.httpMethod = "POST"

        let requestBody = DataCollectorRequest(meta: metadata, events: events)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        request.httpBody = try encoder.encode(requestBody)
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        if let apiKey = self.options.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField:"Authorization")
        }

        let (data, response) = try await networkingService.doRequest(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoFeatureFlagError.httpResponseCastError
        }

        if httpResponse.statusCode == 401 {
            throw GoFeatureFlagError.apiUnauthorizedError(response: httpResponse)
        }
        if httpResponse.statusCode == 403 {
            throw GoFeatureFlagError.forbiddenError(response: httpResponse)
        }
        if httpResponse.statusCode >= 400 {
            throw GoFeatureFlagError.unexpectedResponseError(response: httpResponse)
        }

        do {
            let response = try JSONDecoder().decode(DataCollectorResponse.self, from: data)
            return (response, httpResponse)
        } catch {
            throw GoFeatureFlagError.unmarshallError(error: error)
        }
    }
}
