import Foundation
import OpenFeature
@testable import GOFeatureFlag

class MockNetworkingService: NetworkingService {
    var mockData: Data?
    var mockStatus: Int
    var mockURLResponse: URLResponse?
    var callCounter = 0

    init(mockData: Data? = nil, mockStatus: Int = 200, mockURLResponse: URLResponse? = nil) {
        self.mockData = mockData
        if mockData == nil {
            self.mockData = defaultResponse.data(using: .utf8)
        }
        self.mockURLResponse = mockURLResponse
        self.mockStatus = mockStatus
    }

    func doRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCounter+=1
        guard let jsonDictionary = try JSONSerialization.jsonObject(with: request.httpBody!, options: []) as? [String: Any] else {
            throw OpenFeatureError.invalidContextError
        }
        guard let targetingKey = ((jsonDictionary["context"] as! [String:Any])["targetingKey"] as? String) else {
            throw OpenFeatureError.targetingKeyMissingError
        }


        var data = mockData ?? Data()
        var headers: [String: String]? = nil
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
            "additionalProp2": true,
            "additionalProp3": true
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
