import Foundation
import OpenFeature
@testable import OFREP
@testable import GOFeatureFlag

public class MockNetworkingService: NetworkingService {
    var mockData: Data?
    var mockStatus: Int
    var mockURLResponse: URLResponse?

    // The data collector flushes on a background timer, so these are written
    // from a background task while tests read them from the test thread.
    // Guard them with a lock rather than racing on bare vars.
    private let lock = NSLock()
    private var _callCounter = 0
    private var _dataCollectorCallCounter = 0
    private var _dataCollectorEventCounter = 0
    private var _requests: [URLRequest] = []

    var callCounter: Int { withLock { _callCounter } }
    var dataCollectorCallCounter: Int { withLock { _dataCollectorCallCounter } }
    var dataCollectorEventCounter: Int { withLock { _dataCollectorEventCounter } }
    var requests: [URLRequest] { withLock { _requests } }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public init(mockStatus: Int = 200) {
        self.mockStatus = mockStatus
    }

    public func doRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        withLock {
            _requests.append(request)
            _callCounter += 1
        }
        let isDataCollector = request.url?.absoluteString.contains("/v1/data/collector") ?? false
        let isBulkEvaluation = request.url?.absoluteString.contains("/ofrep/v1/evaluate/flags") ?? false
        if isDataCollector {
            let requestBody = try JSONDecoder().decode(DataCollectorRequest.self, from: request.httpBody!)
            // Count every flush and every event it carries. Previously events
            // were only counted when a batch held more than one, so a batch of
            // exactly one was silently dropped from the total - which made the
            // event counts depend on how the flush timer happened to split the
            // batch.
            let eventCount = requestBody.events?.count ?? 0
            withLock {
                _dataCollectorCallCounter += 1
                _dataCollectorEventCounter += eventCount
            }
            if eventCount > 1 {
                let dataCollectorResponse = DataCollectorResponse(ingestedContentCount: eventCount)
                let responseBody = try JSONEncoder().encode(dataCollectorResponse)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (responseBody, response)
            }

            if request.allHTTPHeaderFields?["Authorization"] != nil || request.allHTTPHeaderFields?["X-API-Key"] != nil{
                if request.allHTTPHeaderFields?["Authorization"] == "Bearer apiKey1" ||  request.allHTTPHeaderFields?["X-API-Key"] == "apiKey1"{
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (validResponse.data(using: .utf8)!, response)
                }

                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return ("{}".data(using: .utf8)!, response)
            }

            if self.mockStatus == 200 {
                let response = HTTPURLResponse(url: request.url!, statusCode: self.mockStatus, httpVersion: nil, headerFields: nil)!
                return (validResponse.data(using: .utf8)!, response)
            }

            if self.mockStatus == 401 {
                let response = HTTPURLResponse(url: request.url!, statusCode: self.mockStatus, httpVersion: nil, headerFields: nil)!
                return ("{}".data(using: .utf8)!, response)
            }

            if self.mockStatus == 403 {
                let response = HTTPURLResponse(url: request.url!, statusCode: self.mockStatus, httpVersion: nil, headerFields: nil)!
                return ("{}".data(using: .utf8)!, response)
            }

            if self.mockStatus == 400 {
                // Invalid json response
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (invalidResponse.data(using: .utf8)!, response)
            }

            if self.mockStatus >= 400 {
                let response = HTTPURLResponse(url: request.url!, statusCode: self.mockStatus, httpVersion: nil, headerFields: nil)!
                return ("{}".data(using: .utf8)!, response)
            }
        }

        if isBulkEvaluation {
            let headers = ["ETag": "33a64df551425fcc55e"]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            return (defaultResponse.data(using: .utf8)!, response)
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return ("{}".data(using: .utf8)!, response)
    }

    let validResponse = "{\"ingestedContentCount\":1}"
    let invalidResponse = "{\"ingestedContentCount\":1"
    private let defaultResponse = """
    {
      "flags": [
        {
          "value": true,
          "key": "my-flag",
          "reason": "STATIC",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        },
        {
          "value": true,
          "key": "bool-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        },
        {
          "value": 1234,
          "key": "int-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        },
        {
          "value": 12.34,
          "key": "double-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        },
        {
          "value": "1234value",
          "key": "string-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        },
        {
          "value": {"testValue":{"toto":1234}},
          "key": "object-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        },
        {
          "value": [1234, 5678],
          "key": "array-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantA",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": true,
            "additionalProp3": true
          }
        }
      ]
    }
"""
}
