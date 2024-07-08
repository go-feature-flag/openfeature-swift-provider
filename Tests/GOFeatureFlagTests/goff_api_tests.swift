import XCTest
import Foundation
import OpenFeature
import OFREP
@testable import GOFeatureFlag

class GoffApiTests: XCTestCase {
    var options = GoFeatureFlagProviderOptions(endpoint: "http://localhost:1031/")

    func testShouldReturnAValidDataCollector() async throws{
        let mockService = MockNetworkingService(mockStatus: 200)
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)
        
        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970), key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            let (response, _) = try await goffAPI.postDataCollector(events: events)
            XCTAssertEqual(response.ingestedContentCount, 1)
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAnErrorIf401HttpResponse() async throws{
        let mockService = MockNetworkingService(mockStatus: 401)
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970), key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            let (response, _) = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.apiUnauthorizedError, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            switch error {
            case .apiUnauthorizedError:
                break
            default:
                XCTFail("Caught an unexpected GoFeatureFlagError error type: \(error)")
            }
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAnErrorIf403HttpResponse() async throws{
        let mockService = MockNetworkingService(mockStatus: 403)
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970), key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            let (response, _) = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.forbiddenError, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            switch error {
            case .forbiddenError:
                break
            default:
                XCTFail("Caught an unexpected GoFeatureFlagError error type: \(error)")
            }
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAValidResponseIfUsingApiKey() async throws{
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = GoFeatureFlagProviderOptions(endpoint: "http://localhost:1031/", apiKey: "apiKey1")
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970), 
                         key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            let (response, _) = try await goffAPI.postDataCollector(events: events)
            XCTAssertEqual(response.ingestedContentCount, 1)
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAnErrorIfUsingInvalidApiKey() async throws{
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = GoFeatureFlagProviderOptions(endpoint: "http://localhost:1031/", apiKey: "apiKey2")
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970),
                         key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            (_,_) = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.apiUnauthorizedError, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            switch error {
            case .apiUnauthorizedError:
                break
            default:
                XCTFail("Caught an unexpected GoFeatureFlagError error type: \(error)")
            }
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAnErrorIfNoEventSend() async throws{
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = GoFeatureFlagProviderOptions(endpoint: "http://localhost:1031/")
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = []

        do {
            let _ = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.noEventToSend, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            XCTAssertEqual(error, GoFeatureFlagError.noEventToSend, "Expected .noEventToSend error, got \(error) instead.")
        } catch {
            XCTFail("Expected GoFeatureFlagError.noEventToSend but got a different error: \(error).")
        }
    }

    func testShouldReturnAnErrorIfNoEventSendNil() async throws{
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = GoFeatureFlagProviderOptions(endpoint: "http://localhost:1031/")
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        do {
            let _ = try await goffAPI.postDataCollector(events: nil)
            XCTFail("Expected to throw GoFeatureFlagError.noEventToSend, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            XCTAssertEqual(error, GoFeatureFlagError.noEventToSend, "Expected .noEventToSend error, got \(error) instead.")
        } catch {
            XCTFail("Expected GoFeatureFlagError.noEventToSend but got a different error: \(error).")
        }
    }


    func testShouldReturnAnErrorIfInvalidEndpoint() async throws{
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = GoFeatureFlagProviderOptions(endpoint: "")
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970),
                         key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            (_,_) = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.invalidEndpoint, but no error was thrown.")
        } catch _ as InvalidOptions {
            // nothing to do here, this is a success
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAnErrorIf500HttpResponse() async throws{
        let mockService = MockNetworkingService(mockStatus: 500)
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)

        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970), key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            (_, _) = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.unexpectedResponseError, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            switch error {
            case .unexpectedResponseError:
                break
            default:
                XCTFail("Caught an unexpected GoFeatureFlagError error type: \(error)")
            }
        } catch {
            XCTFail("exception thrown when doing the evaluation: \(error)")
        }
    }

    func testShouldReturnAnErrorIfNoInvalidJsonInResponse() async throws{
        let mockService = MockNetworkingService(mockStatus: 400)
        let options = GoFeatureFlagProviderOptions(endpoint: "http://localhost:1031/")
        let goffAPI = GoFeatureFlagAPI(networkingService: mockService, options: options)
        let events: [FeatureEvent] = [
            FeatureEvent(kind: "feature", userKey: "981f2662-1fb4-4732-ac6d-8399d9205aa9", creationDate: Int64(Date().timeIntervalSince1970),
                         key: "flag-1", variation: "enabled", value: JSONValue.bool(true), default: false, version: nil, source: "PROVIDER_CACHE")
        ]
        do {
            let _ = try await goffAPI.postDataCollector(events: events)
            XCTFail("Expected to throw GoFeatureFlagError.noEventToSend, but no error was thrown.")
        } catch let error as GoFeatureFlagError {
            switch error {
            case .unmarshallError:
                break
            default:
                XCTFail("Caught an unexpected GoFeatureFlagError error type: \(error)")
            }
        } catch {
            XCTFail("Expected GoFeatureFlagError.noEventToSend but got a different error: \(error).")
        }
    }
}
