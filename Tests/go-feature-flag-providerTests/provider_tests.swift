import XCTest
import Combine
import Foundation
import OpenFeature
@testable import go_feature_flag_provider

class ProviderTests: XCTestCase {
    var defaultEvaluationContext: MutableContext!
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        cancellables = []
        defaultEvaluationContext = MutableContext()
        defaultEvaluationContext.setTargetingKey(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        defaultEvaluationContext.add(key: "email", value: Value.string("john.doe@gofeatureflag.org"))
        defaultEvaluationContext.add(key: "name", value: Value.string("John Doe"))
        defaultEvaluationContext.add(key: "age", value: Value.integer(2))
        defaultEvaluationContext.add(key: "category", value: Value.double(2.2))
        defaultEvaluationContext.add(key: "struct", value: Value.structure(["test" : Value.string("test")]))
        defaultEvaluationContext.add(key: "list", value: Value.list([Value.string("test1"), Value.string("test2")]))
    }

    override func tearDown() {
        cancellables = []
        defaultEvaluationContext = nil
        super.tearDown()
    }

    func testShouldBeInFATALStatusIf401ErrorDuringInitialise() async {
        // TODO: PROVIDER_FATAL event does not exist for now, we will test that the provider is in ERROR
        // issue open for the fatal state: https://github.com/open-feature/swift-sdk/issues/40

        let mockResponse = "{}"
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 401)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            // TODO: Move to FATAL when the event will be handled by the SDK
            if(event != ProviderEvent.error){
                XCTFail("If OFREP API returns a 401 we should receive a FATAL event, received: \(event)")
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 3.0)
    }

    func testShouldBeInFATALStatusIf403ErrorDuringInitialise() async {
        // TODO: PROVIDER_FATAL event does not exist for now, we will test that the provider is in ERROR
        // issue open for the fatal state: https://github.com/open-feature/swift-sdk/issues/40

        let mockResponse = "{}"
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 403)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            // TODO: Move to FATAL when the event will be handled by the SDK
            if(event != ProviderEvent.error){
                XCTFail("If OFREP API returns a 403 we should receive a FATAL event, received: \(event)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 3.0)
    }

    func testShouldBeInErrorStatusIf429ErrorDuringInitialise() async {
        let mockResponse = "{}"
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 429)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.error){
                XCTFail("If OFREP API returns a 429 we should receive an ERROR event, received: \(event)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 3.0)
    }

    func testShouldBeInErrorStatusIfErrorTargetingKeyIsMissing() async {
        let mockResponse = """
{
    "errorCode": "TARGETING_KEY_MISSING",
    "errorDetails": "Error details about TARGETING_KEY_MISSING"

}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.error){
                XCTFail("If OFREP API returns a 400 for TARGETING_KEY_MISSING we should receive an ERROR event, received: \(event)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 3)
    }

    func testShouldBeInErrorStatusIfErrorInvalidContext() async {
        let mockResponse = """
{
    "errorCode": "INVALID_CONTEXT",
    "errorDetails": "Error details about INVALID_CONTEXT"
}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()


        let expectation = XCTestExpectation(description: "waiting 1st event")
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.error){
                XCTFail("If OFREP API returns a 400 for INVALID_CONTEXT we should receive an ERROR event, received: \(event)")
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 3)
    }

    func testShouldBeInErrorStatusIfErrorParseError() async {
        let mockResponse = """
{
    "errorCode": "PARSE_ERROR",
    "errorDetails": "Error details about PARSE_ERROR"
}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.error){
                XCTFail("If OFREP API returns a 400 for PARSE_ERROR we should receive an ERROR event, received: \(event)")
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 3)
    }

    func testShouldReturnAFlagNotFoundErrorIfTheFlagDoesNotExist() async {
        let mockService = MockNetworkingService( mockStatus: 200)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 3)

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "non-existant-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, ErrorCode.flagNotFound)
    }

    func testShouldReturnEvaluationDetailsIfTheFlagExists() async {
        let mockService = MockNetworkingService( mockStatus: 400)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 3)

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.flagKey, "my-flag")
        XCTAssertEqual(details.reason, "STATIC")
        XCTAssertEqual(details.variant, "variantA")
    }

    func testShouldReturnParseErrorIfTheAPIReturnTheError() async {
        let mockResponse = """
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
      "key": "my-other-flag",
      "errorCode": "PARSE_ERROR",
      "errorDetails": "Error details about PARSE_ERROR"
    }
  ]
}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expectation = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 3)

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "my-other-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, ErrorCode.parseError)
        XCTAssertEqual(details.value, false)
        XCTAssertEqual(details.errorMessage, "Parse error: Error details about PARSE_ERROR")
        XCTAssertEqual(details.flagKey, "my-other-flag")
        XCTAssertEqual(details.reason, "error")
        XCTAssertEqual(details.variant, nil)
    }


    func testShouldSendAContextChangedEventIfContextChanged() async {
        let mockService = MockNetworkingService(mockStatus: 200)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService
        )
        let provider = GoFeatureFlagProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        let expect = XCTestExpectation(description: "waiting 1st event")
        _ = api.observe().sink{ event in
            switch event{
            case ProviderEvent.ready:
                expect.fulfill()
            default:
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
                expect.fulfill()
            }
        }
        await fulfillment(of: [expect], timeout: 3)

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.flagKey, "my-flag")
        XCTAssertEqual(details.reason, "STATIC")
        XCTAssertEqual(details.variant, "variantA")

        let newContext = MutableContext()
        newContext.setTargetingKey(targetingKey: "second-context")
        newContext.add(key: "email", value: Value.string("batman@gofeatureflag.org"))

        let expectation1 = expectation(description: "event 1")
        let expectation2 = expectation(description: "event 2")
        let expectation3 = expectation(description: "event 3")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            receivedEvents.append(event)
            switch receivedEvents.count{
            case 1:
                expectation1.fulfill()
            case 2:
                expectation2.fulfill()
            case 3:
                expectation3.fulfill()
            default:
                break
            }

        }.store(in: &cancellables)
        api.setEvaluationContext(evaluationContext: newContext)
        await fulfillment(of:[expectation1, expectation2, expectation3], timeout: 5)
        let expectedEvents: [ProviderEvent] = [.ready, .stale, .ready]
        XCTAssertEqual(receivedEvents, expectedEvents, "The events were not received in the expected order.")

        let details2 = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details2.errorCode, nil)
        XCTAssertEqual(details2.value, false)
        XCTAssertEqual(details2.errorMessage, nil)
        XCTAssertEqual(details2.flagKey, "my-flag")
        XCTAssertEqual(details2.reason, "TARGETING_MATCH")
        XCTAssertEqual(details2.variant, "variantB")
    }


    func testShouldNotTryToCallTheAPIBeforeRetryAfterHeader() async {
        let mockService = MockNetworkingService(mockStatus: 200)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = GoFeatureFlagProvider(options: options)
        let api = OpenFeatureAPI()

        let ctx = MutableContext()
        ctx.setTargetingKey(targetingKey: "429")

        await api.setProviderAndWait(provider: provider, initialContext: ctx)

        let expectation1 = expectation(description: "Ready event")
        let expectation2 = expectation(description: "Stale event")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            receivedEvents.append(event)
            switch receivedEvents.count{
            case 1:
                expectation1.fulfill()
            case 2:
                expectation2.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        await fulfillment(of:[expectation1, expectation2], timeout: 5)
        let expectedEvents: [ProviderEvent] = [.ready, .stale]
        XCTAssertEqual(receivedEvents, expectedEvents, "The events were not received in the expected order.")
        XCTAssertEqual(2, mockService.callCounter, "we should stop calling the API if we got a 429")
    }

    func testShouldSendAConfigurationChangedEventWhenNewFlagIsSend() async {
        let mockResponse = """
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
    }
  ]
}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 200)

        let options = GoFeatureFlagProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = GoFeatureFlagProvider(options: options)
        let api = OpenFeatureAPI()

        let ctx = MutableContext()
        ctx.setTargetingKey(targetingKey: "test-change-config")

        await api.setProviderAndWait(provider: provider, initialContext: ctx)
        let client = api.getClient()

        let details = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.flagKey, "my-flag")
        XCTAssertEqual(details.reason, "STATIC")
        XCTAssertEqual(details.variant, "variantA")

        let expectation1 = expectation(description: "Ready event")
        let expectation2 = expectation(description: "ConfigurationChanged event")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            receivedEvents.append(event)
            switch receivedEvents.count{
            case 1:
                expectation1.fulfill()
            case 2:
                expectation2.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        await fulfillment(of:[expectation1, expectation2], timeout: 7)
        let expectedEvents: [ProviderEvent] = [.ready, .configurationChanged]
        XCTAssertEqual(receivedEvents, expectedEvents, "The events were not received in the expected order.")

        let details2 = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details2.errorCode, nil)
        XCTAssertEqual(details2.value, false)
        XCTAssertEqual(details2.errorMessage, nil)
        XCTAssertEqual(details2.flagKey, "my-flag")
        XCTAssertEqual(details2.reason, "TARGETING_MATCH")
        XCTAssertEqual(details2.variant, "variantB")
    }
}
