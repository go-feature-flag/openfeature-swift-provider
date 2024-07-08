import Foundation
import OpenFeature
@testable import OFREP

public class MockNetworkingService: NetworkingService {
    var mockData: Data?
    var mockStatus: Int
    var mockURLResponse: URLResponse?
    var callCounter = 0

    public init(mockStatus: Int = 200) {
        self.mockStatus = mockStatus
    }

    public func doRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        let isDataCollector = request.url?.absoluteString.contains("/v1/data/collector") ?? false
        if isDataCollector {

            if request.allHTTPHeaderFields?["Authorization"] != nil {
                if request.allHTTPHeaderFields?["Authorization"] == "Bearer apiKey1" {
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
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return ("{}}".data(using: .utf8)!, response)
            }
        }



//        callCounter+=1
//        guard let jsonDictionary = try JSONSerialization.jsonObject(with: request.httpBody!, options: []) as? [String: Any] else {
//            throw OpenFeatureError.invalidContextError
//        }
//        guard let targetingKey = ((jsonDictionary["context"] as! [String:Any])["targetingKey"] as? String) else {
//            throw OpenFeatureError.targetingKeyMissingError
//        }
//
//
//        var data = mockData ?? Data()
//        var headers: [String: String]? = nil
//        if mockStatus == 429 || (targetingKey == "429" && callCounter >= 2){
//            headers = ["Retry-After": "120"]
//            mockStatus = 429
//            let response = HTTPURLResponse(url: request.url!, statusCode: mockStatus, httpVersion: nil, headerFields: headers)!
//            return (data, response)
//        }
//
//        if mockStatus == 200 {
//            mockStatus = 200
//            headers = ["ETag": "33a64df551425fcc55e4d42a148795d9f25f89d4"]
//        }
//
//        if targetingKey == "second-context" || (targetingKey == "test-change-config" && callCounter >= 3){
//            headers = ["ETag": "differentEtag33a64df551425fcc55e"]
//            data = secondResponse.data(using: .utf8)!
//            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
//            return (data, response)
//        }
//
//        if request.value(forHTTPHeaderField: "If-None-Match") == "33a64df551425fcc55e4d42a148795d9f25f89d4" {
//            mockStatus = 304
//        }
//
        let response = mockURLResponse ?? HTTPURLResponse(url: request.url!, statusCode: mockStatus, httpVersion: nil, headerFields: nil)!
        return (mockData!, response)
    }
    
    let validResponse = "{\"ingestedContentCount\":1}"
    let invalidResponse = "{\"ingestedContentCount\":1"
}
