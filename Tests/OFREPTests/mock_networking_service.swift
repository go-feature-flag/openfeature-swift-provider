import Foundation
import OpenFeature
@testable import OFREP

public class MockNetworkingService: NetworkingService {
    var mockData: Data?
    var mockStatus: Int
    var mockURLResponse: URLResponse?
    var callCounter = 0

    public init(mockData: Data? = nil, mockStatus: Int = 200, mockURLResponse: URLResponse? = nil) {
        self.mockData = mockData
        if mockData == nil {
            self.mockData = defaultResponse.data(using: .utf8)
        }
        self.mockURLResponse = mockURLResponse
        self.mockStatus = mockStatus
    }

    public func doRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCounter+=1
        guard let jsonDictionary = try JSONSerialization.jsonObject(with: request.httpBody!, options: []) as? [String: Any] else {
            throw OpenFeatureError.invalidContextError
        }
        guard let targetingKey = ((jsonDictionary["context"] as! [String:Any])["targetingKey"] as? String) else {
            throw OpenFeatureError.targetingKeyMissingError
        }


        var data = mockData ?? Data()
        var headers: [String: String]? = nil

        // Rate limits the second call only, with a retry window short enough for a test, so the
        // following polls reach the API again and the provider can leave the stale state.
        if targetingKey == "429-recover" {
            if callCounter == 2 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 429, httpVersion: nil,
                    headerFields: ["Retry-After": "1"])!
                return (data, response)
            }
            // A fresh ETag every time, so the provider never gets a 304 and always sees changes.
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["ETag": "429-recover-\(callCounter)"])!
            return (data, response)
        }

        // Answers slowly, so a test can start a second context change while this one is still
        // in flight and check which of the two responses ends up in the cache.
        if targetingKey == "slow-context" {
            try await Task.sleep(nanoseconds: 500_000_000)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["ETag": "slow-context"])!
            return (data, response)
        }

        // Same delay as slow-context, but ends in a 429: used to check that a cancelled
        // reconcile does not emit .stale or install a Retry-After window.
        if targetingKey == "slow-429" {
            try await Task.sleep(nanoseconds: 500_000_000)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "120"])!
            return (data, response)
        }

        // Rate limits every call after the first one, but without a Retry-After header: the
        // provider has no window to respect and has to reach the API again on the next poll.
        if targetingKey == "429-no-retry-after" {
            if callCounter == 2 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            // A fresh ETag every time, so the provider never gets a 304 and always sees changes.
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["ETag": "429-no-retry-after-\(callCounter)"])!
            return (data, response)
        }

        // Rate limits every call after the first one with a Retry-After expressed as an
        // HTTP-date far in the future, so the provider must stop calling the API.
        if targetingKey == "429-http-date" {
            if callCounter == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["ETag": "429-http-date"])!
                return (data, response)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "Wed, 21 Oct 2099 07:28:00 GMT"])!
            return (data, response)
        }

        // Rate limits every call after the first one with the Retry-After header name spelled in
        // lowercase, as it commonly arrives over HTTP/2. The provider must still honour the window,
        // which requires a case-insensitive header lookup.
        if targetingKey == "429-lowercase-retry-after" {
            if callCounter == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["ETag": "429-lowercase-retry-after"])!
                return (data, response)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["retry-after": "120"])!
            return (data, response)
        }

        // Answers once, then rejects everything with a 401: used both for a context change and
        // for a poll that becomes unauthorized after the provider is initialised.
        if targetingKey == "401-after-first" {
            if callCounter == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["ETag": "401-after-first"])!
                return (data, response)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        // Answers once, then returns a bulk evaluation error the server decides on. It is not an
        // OfrepError, so it exercises the paths handling an OpenFeatureError.
        if targetingKey == "error-after-first" {
            if callCounter == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["ETag": "error-after-first"])!
                return (data, response)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (bulkErrorResponse.data(using: .utf8)!, response)
        }

        // Fails the initial call with a transient 5xx, then answers 200 with a fresh ETag on every
        // following poll: used to check the provider still starts polling after a failed
        // initialisation and recovers from error to ready once the API answers again.
        if targetingKey == "fail-init-then-recover" {
            if callCounter == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["ETag": "fail-init-then-recover-\(callCounter)"])!
            return (data, response)
        }

        if mockStatus == 429 || (targetingKey == "429" && callCounter >= 2){
            headers = ["Retry-After": "120"]
            mockStatus = 429
            let response = HTTPURLResponse(url: request.url!, statusCode: mockStatus, httpVersion: nil, headerFields: headers)!
            return (data, response)
        }

        if mockStatus == 200 {
            mockStatus = 200
            headers = ["ETag": "33a64df551425fcc55e4d42a148795d9f25f89d4"]
        }

        if targetingKey == "second-context" || (targetingKey == "test-change-config" && callCounter >= 3){
            headers = ["ETag": "differentEtag33a64df551425fcc55e"]
            data = secondResponse.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            return (data, response)
        }

        if request.value(forHTTPHeaderField: "If-None-Match") == "33a64df551425fcc55e4d42a148795d9f25f89d4" {
            mockStatus = 304
        }

        let response = mockURLResponse ?? HTTPURLResponse(url: request.url!, statusCode: mockStatus, httpVersion: nil, headerFields: headers)!
        return (data, response)
    }

    /// A bulk evaluation the server rejected as a whole, as opposed to a single flag in error.
    private let bulkErrorResponse = """
    {
      "errorCode": "INVALID_CONTEXT",
      "errorDetails": "Error details about INVALID_CONTEXT"
    }
    """

    private let secondResponse = """
    {
      "flags": [
        {
          "value": false,
          "key": "my-flag",
          "reason": "TARGETING_MATCH",
          "variant": "variantB",
          "metadata": {
            "additionalProp1": true,
            "additionalProp2": "value",
            "additionalProp3": 123
          }
        }
      ]
    }
    """

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
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    },
    {
      "value": true,
      "key": "bool-flag",
      "reason": "TARGETING_MATCH",
      "variant": "variantA",
      "metadata": {
        "additionalProp1": true,
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    },
    {
      "value": 1234,
      "key": "int-flag",
      "reason": "TARGETING_MATCH",
      "variant": "variantA",
      "metadata": {
        "additionalProp1": true,
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    },
    {
      "value": 12.34,
      "key": "double-flag",
      "reason": "TARGETING_MATCH",
      "variant": "variantA",
      "metadata": {
        "additionalProp1": true,
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    },
    {
      "value": "1234value",
      "key": "string-flag",
      "reason": "TARGETING_MATCH",
      "variant": "variantA",
      "metadata": {
        "additionalProp1": true,
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    },
    {
      "value": {"testValue":{"toto":1234}},
      "key": "object-flag",
      "reason": "TARGETING_MATCH",
      "variant": "variantA",
      "metadata": {
        "additionalProp1": true,
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    },
    {
      "value": [1234, 5678],
      "key": "array-flag",
      "reason": "TARGETING_MATCH",
      "variant": "variantA",
      "metadata": {
        "additionalProp1": true,
        "additionalProp2": "value",
        "additionalProp3": 123
      }
    }
  ]
}
"""
}
