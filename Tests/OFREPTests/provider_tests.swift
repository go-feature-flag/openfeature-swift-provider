import XCTest
import Combine
import Foundation
import Logging
import OpenFeature
@testable import OFREP

class ProviderTests: XCTestCase {
    var defaultEvaluationContext: ImmutableContext!
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        cancellables = []
        defaultEvaluationContext = ImmutableContext(
            targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0",
            structure: ImmutableStructure(attributes: [
                "email": Value.string("john.doe@gofeatureflag.org"),
                "name": Value.string("John Doe"),
                "age": Value.integer(2),
                "category": Value.double(2.2),
                "struct": Value.structure(["test": Value.string("test")]),
                "list": Value.list([Value.string("test1"), Value.string("test2")])
            ])
        )
    }

    override func tearDown() {
        cancellables = []
        defaultEvaluationContext = nil
        // OpenFeatureAPI.shared is global state, do not leak a logger to the other tests.
        OpenFeatureAPI.shared.setLogger(nil)
        super.tearDown()
    }

    func testProviderMetadataName() async {
        let options = OfrepProviderOptions(endpoint: "https://localhost:1031")
        let provider = OfrepProvider(options: options)
        XCTAssertEqual(provider.metadata.name, "OFREP provider")
    }

    func testShouldBeInFATALStatusIf401ErrorDuringInitialise() async {
        let mockResponse = "{}"
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 401)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        XCTAssertEqual(api.getProviderStatus(), ProviderStatus.fatal)
    }

    func testShouldBeInFATALStatusIf403ErrorDuringInitialise() async {
        let mockResponse = "{}"
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 403)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        XCTAssertEqual(api.getProviderStatus(), ProviderStatus.fatal)
    }

    func testShouldBeInErrorStatusIf429ErrorDuringInitialise() async {
        let mockResponse = "{}"
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 429)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.error(ProviderEventDetails(message: "The operation couldn’t be completed. (OFREP.OfrepError error 3.)"))){
                XCTFail("If OFREP API returns a 429 we should receive an ERROR event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3.0)
        cancellable.cancel()
    }

    func testShouldEmitAGeneralErrorIfInitialiseReceivesAnUnknownStatus() async {
        // A 304 on the very first call makes the bulk evaluation report
        // successNoChanges, which is not a valid state to initialise from.
        let mockService = MockNetworkingService(mockStatus: 304)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0, // no polling, we only care about the initialisation
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)

        let expectation = XCTestExpectation(description: "waiting for the error event")
        var receivedEvents = [ProviderEvent]()
        let cancellable = provider.observe().sink { event in
            receivedEvents.append(event)
            expectation.fulfill()
        }
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3.0)
        cancellable.cancel()

        let expectedEvents: [ProviderEvent] = [
            .error(
                ProviderEventDetails(
                    message: "General error: impossible to initialize the provider, receive unknown status",
                    errorCode: .general))
        ]
        XCTAssertEqual(receivedEvents, expectedEvents)
        XCTAssertEqual(provider.status, ProviderStatus.error)
    }

    func testShouldMoveFromNotReadyToReadyStatusOnInitialise() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0, // no polling, we only care about the initialisation
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        XCTAssertEqual(provider.status, ProviderStatus.notReady)

        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        XCTAssertEqual(provider.status, ProviderStatus.ready)
        XCTAssertEqual(api.getProviderStatus(), ProviderStatus.ready)
    }

    func testShouldBeInErrorStatusIfErrorTargetingKeyIsMissing() async {
        let mockResponse = """
{
    "errorCode": "TARGETING_KEY_MISSING",
    "errorDetails": "Error details about TARGETING_KEY_MISSING"

}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            let expected = ProviderEvent.error(
                ProviderEventDetails(message: "Targeting key missing in resolve", errorCode: .targetingKeyMissing))
            if(event != expected){
                XCTFail("If OFREP API returns a 400 for TARGETING_KEY_MISSING we should receive an ERROR event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
    }

    func testShouldBeInErrorStatusIfErrorInvalidContext() async {
        let mockResponse = """
{
    "errorCode": "INVALID_CONTEXT",
    "errorDetails": "Error details about INVALID_CONTEXT"
}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        
        let cancellable = api.observe().sink{ event in
            let expected = ProviderEvent.error(
                ProviderEventDetails(message: "Invalid or missing context", errorCode: .invalidContext))
            if(event != expected){
                XCTFail("If OFREP API returns a 400 for INVALID_CONTEXT we should receive an ERROR event, received: \(String(describing: event))")
            }
            expectation.fulfill()
        }

        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
    }

    func testShouldBeInErrorStatusIfErrorParseError() async {
        let mockResponse = """
{
    "errorCode": "PARSE_ERROR",
    "errorDetails": "Error details about PARSE_ERROR"
}
"""
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 400)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)

        let api = OpenFeatureAPI()
        
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            let expected = ProviderEvent.error(
                ProviderEventDetails(
                    message: "Parse error: Error details about PARSE_ERROR", errorCode: .parseError))
            if(event != expected){
                XCTFail("If OFREP API returns a 400 for PARSE_ERROR we should receive an ERROR event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }

        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
    }

    func testShouldReturnAFlagNotFoundErrorIfTheFlagDoesNotExist() async {
        let mockService = MockNetworkingService( mockStatus: 200)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)

        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "non-existant-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, ErrorCode.flagNotFound)
    }

    func testShouldReturnEvaluationDetailsIfTheFlagExists() async {
        let mockService = MockNetworkingService( mockStatus: 200)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        
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
        let mockService = MockNetworkingService(mockData:  mockResponse.data(using: .utf8), mockStatus: 200)

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        
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

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)

        let api = OpenFeatureAPI()
        let expect = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            switch event{
            case .ready:
                expect.fulfill()
            default:
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
                expect.fulfill()
            }
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expect], timeout: 3)
        cancellable.cancel()

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.flagKey, "my-flag")
        XCTAssertEqual(details.reason, "STATIC")
        XCTAssertEqual(details.variant, "variantA")

        let newContext = ImmutableContext(
            targetingKey: "second-context",
            structure: ImmutableStructure(attributes: [
                "email": Value.string("batman@gofeatureflag.org")
            ])
        )

        let expectation1 = expectation(description: "event 1")
        let expectation2 = expectation(description: "event 2")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            if event == .ready() {
                return // The API replays the current ready status to new subscribers.
            }
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
        api.setEvaluationContext(evaluationContext: newContext)
        await fulfillment(of:[expectation1, expectation2], timeout: 5)
        let expectedEvents: [ProviderEvent] = [.reconciling(), .contextChanged()]
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

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        let ctx = ImmutableContext(targetingKey: "429")

    
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
        await api.setProviderAndWait(provider: provider, initialContext: ctx)
        await fulfillment(of:[expectation1, expectation2], timeout: 5)
        let expectedEvents: [ProviderEvent] = [.ready(), .stale()]
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

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        let ctx = ImmutableContext(targetingKey: "test-change-config")

        await api.setProviderAndWait(provider: provider, initialContext: ctx)
        let client = api.getClient()

        let details = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.flagKey, "my-flag")
        XCTAssertEqual(details.reason, "STATIC")
        XCTAssertEqual(details.variant, "variantA")

        let expectation1 = expectation(description: "ConfigurationChanged event")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            if event == .ready() {
                return // The API replays the current ready status to new subscribers.
            }
            receivedEvents.append(event)
            switch receivedEvents.count{
            case 1:
                expectation1.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        await fulfillment(of:[expectation1], timeout: 5)
        let expectedEvents: [ProviderEvent] = [.configurationChanged()]
        XCTAssertEqual(receivedEvents, expectedEvents, "The events were not received in the expected order.")

        let details2 = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        XCTAssertEqual(details2.errorCode, nil)
        XCTAssertEqual(details2.value, false)
        XCTAssertEqual(details2.errorMessage, nil)
        XCTAssertEqual(details2.flagKey, "my-flag")
        XCTAssertEqual(details2.reason, "TARGETING_MATCH")
        XCTAssertEqual(details2.variant, "variantB")
    }

    func testShouldReturnAValidEvaluationForBool() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        
        let client = api.getClient()
        let details = client.getBooleanDetails(key: "bool-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.flagKey, "bool-flag")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.variant, "variantA")
        XCTAssertEqual(details.flagMetadata.count, 3)
        XCTAssertEqual(details.flagMetadata["additionalProp2"], FlagMetadataValue.string("value"))
        XCTAssertEqual(details.flagMetadata["additionalProp1"], FlagMetadataValue.boolean(true))
        XCTAssertEqual(details.flagMetadata["additionalProp3"], FlagMetadataValue.integer(123))
    }

    func testShouldReturnAValidEvaluationForInt() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()

        let client = api.getClient()
        let details = client.getIntegerDetails(key: "int-flag", defaultValue: 1)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.value, 1234)
        XCTAssertEqual(details.flagKey, "int-flag")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.variant, "variantA")
        XCTAssertEqual(details.flagMetadata.count, 3)
        XCTAssertEqual(details.flagMetadata["additionalProp2"], FlagMetadataValue.string("value"))
        XCTAssertEqual(details.flagMetadata["additionalProp1"], FlagMetadataValue.boolean(true))
        XCTAssertEqual(details.flagMetadata["additionalProp3"], FlagMetadataValue.integer(123))

    }

    func testShouldReturnAValidEvaluationForDouble() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getDoubleDetails(key: "double-flag", defaultValue: 1.1)
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.value, 12.34)
        XCTAssertEqual(details.flagKey, "double-flag")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.variant, "variantA")
        XCTAssertEqual(details.flagMetadata["additionalProp2"], FlagMetadataValue.string("value"))
        XCTAssertEqual(details.flagMetadata["additionalProp1"], FlagMetadataValue.boolean(true))
        XCTAssertEqual(details.flagMetadata["additionalProp3"], FlagMetadataValue.integer(123))
    }

    func testShouldReturnAValidEvaluationForString() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getStringDetails(key: "string-flag", defaultValue: "1")
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.value, "1234value")
        XCTAssertEqual(details.flagKey, "string-flag")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.variant, "variantA")
        XCTAssertEqual(details.flagMetadata["additionalProp2"], FlagMetadataValue.string("value"))
        XCTAssertEqual(details.flagMetadata["additionalProp1"], FlagMetadataValue.boolean(true))
        XCTAssertEqual(details.flagMetadata["additionalProp3"], FlagMetadataValue.integer(123))
    }

    func testShouldReturnAValidEvaluationForArray() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getObjectDetails(key: "array-flag", defaultValue: Value.list([Value.string("1")]))
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.value, Value.list([Value.integer(1234),Value.integer(5678)]))
        XCTAssertEqual(details.flagKey, "array-flag")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.variant, "variantA")
        XCTAssertEqual(details.flagMetadata["additionalProp2"], FlagMetadataValue.string("value"))
        XCTAssertEqual(details.flagMetadata["additionalProp1"], FlagMetadataValue.boolean(true))
        XCTAssertEqual(details.flagMetadata["additionalProp3"], FlagMetadataValue.integer(123))
    }

    func testShouldReturnAValidEvaluationForObject() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getObjectDetails(key: "object-flag", defaultValue: Value.list([Value.string("1")]))
        XCTAssertEqual(details.errorCode, nil)
        XCTAssertEqual(details.errorMessage, nil)
        XCTAssertEqual(details.value, Value.structure(["testValue": Value.structure(["toto":Value.integer(1234)])]))
        XCTAssertEqual(details.flagKey, "object-flag")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.variant, "variantA")
        XCTAssertEqual(details.flagMetadata["additionalProp2"], FlagMetadataValue.string("value"))
        XCTAssertEqual(details.flagMetadata["additionalProp1"], FlagMetadataValue.boolean(true))
        XCTAssertEqual(details.flagMetadata["additionalProp3"], FlagMetadataValue.integer(123))
    }

    func testShouldReturnTypeMismatchBool() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getBooleanDetails(key: "object-flag", defaultValue: false)
        XCTAssertEqual(details.errorCode, ErrorCode.typeMismatch)
        XCTAssertEqual(details.value, false)
        XCTAssertEqual(details.flagKey, "object-flag")
    }

    func testShouldReturnTypeMismatchString() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getStringDetails(key: "object-flag", defaultValue: "default")
        XCTAssertEqual(details.errorCode, ErrorCode.typeMismatch)
        XCTAssertEqual(details.value, "default")
        XCTAssertEqual(details.flagKey, "object-flag")
    }

    func testShouldReturnTypeMismatchInt() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getIntegerDetails(key: "object-flag", defaultValue: 1)
        XCTAssertEqual(details.errorCode, ErrorCode.typeMismatch)
        XCTAssertEqual(details.value, 1)
        XCTAssertEqual(details.flagKey, "object-flag")
    }

    func testShouldReturnTypeMismatchDouble() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getDoubleDetails(key: "object-flag", defaultValue: 1.1)
        XCTAssertEqual(details.errorCode, ErrorCode.typeMismatch)
        XCTAssertEqual(details.value, 1.1)
        XCTAssertEqual(details.flagKey, "object-flag")
    }

    func testShouldReturnTypeMismatchObject() async {
        let mockService = MockNetworkingService( mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            networkService: mockService
        )
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let expectation = XCTestExpectation(description: "waiting 1st event")
        let cancellable = api.observe().sink{ event in
            if(event != ProviderEvent.ready()){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(String(describing: event)))")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()
        let client = api.getClient()
        let details = client.getObjectDetails(key: "bool-flag", defaultValue: Value.list([Value.string("1")]))
        XCTAssertEqual(details.errorCode, ErrorCode.typeMismatch)
        XCTAssertEqual(details.value, Value.list([Value.string("1")]))
        XCTAssertEqual(details.flagKey, "bool-flag")
    }

    func testShouldGoBackToReadyWhenTheAPIAnswersAgainAfterA429() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        let ctx = ImmutableContext(targetingKey: "429-recover")

        let staleExpectation = expectation(description: "Stale event")
        let recoveredExpectation = expectation(description: "Ready event after the retry window")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink { event in
            receivedEvents.append(event)
            switch receivedEvents.count {
            case 2:
                staleExpectation.fulfill()
            case 3:
                recoveredExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        await api.setProviderAndWait(provider: provider, initialContext: ctx)
        await fulfillment(of: [staleExpectation, recoveredExpectation], timeout: 10)

        XCTAssertEqual([.ready(), .stale(), .ready()], Array(receivedEvents.prefix(3)),
                       "The provider should report itself ready again once the API answers.")
        XCTAssertEqual(ProviderStatus.ready, api.getProviderStatus(),
                       "The provider should not stay stale once the retry window has passed.")
    }

    func testShouldKeepTheFlagsOfTheLastContextWhenTwoContextChangesOverlap() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        let contextChanged = expectation(description: "Winning context finished reconciling")
        api.observe().sink { event in
            if event == .contextChanged() {
                contextChanged.fulfill()
            }
        }.store(in: &cancellables)

        // The 1st context answers 500ms later than the 2nd one, so without cancellation its
        // response would land last and overwrite the flags of the context we actually want.
        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "slow-context"))
        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "second-context"))
        await fulfillment(of: [contextChanged], timeout: 3)
        // Give the cancelled slow response time to land if the guard were broken.
        try? await Task.sleep(nanoseconds: 700_000_000)

        let client = api.getClient()
        let details = client.getBooleanDetails(key: "my-flag", defaultValue: true)
        XCTAssertEqual("variantB", details.variant,
                       "The flags of the superseded context should not overwrite the current ones.")
        XCTAssertEqual(false, details.value)
        XCTAssertEqual(ProviderStatus.ready, api.getProviderStatus())
    }

    func testShouldIgnoreACancelledReconcileThatReturns429() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        var receivedEvents = [ProviderEvent]()
        let contextChanged = expectation(description: "Winning context finished reconciling")
        api.observe().sink { event in
            if event == .ready() {
                return // replay of the current status for a new subscriber
            }
            receivedEvents.append(event)
            if event == .contextChanged() {
                contextChanged.fulfill()
            }
        }.store(in: &cancellables)

        // The slow call answers with 429 after 500ms; the fast call must win, and the
        // cancelled 429 must stay silent (no .stale, no Retry-After installed).
        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "slow-429"))
        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "second-context"))
        await fulfillment(of: [contextChanged], timeout: 3)
        try? await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual([.reconciling(), .reconciling(), .contextChanged()], receivedEvents,
                       "A cancelled 429 must not emit .stale after the winning reconcile.")
        XCTAssertEqual(ProviderStatus.ready, api.getProviderStatus())
        let details = api.getClient().getBooleanDetails(key: "my-flag", defaultValue: true)
        XCTAssertEqual("variantB", details.variant)
        XCTAssertEqual(false, details.value)
    }

    func testShouldStayStaleWhenOnContextSetIsRateLimited() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        // First call succeeds; the next evaluation with targetingKey "429" returns 429 and
        // installs a long Retry-After, so the following context change is rate-limited.
        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "429"))

        let firstStale = expectation(description: "First context change hits 429")
        firstStale.assertForOverFulfill = false
        var phase1 = Set<AnyCancellable>()
        api.observe().sink { event in
            if event == .stale() {
                firstStale.fulfill()
            }
        }.store(in: &phase1)

        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "429"))
        await fulfillment(of: [firstStale], timeout: 3)
        phase1.removeAll()
        XCTAssertEqual(ProviderStatus.stale, api.getProviderStatus())

        let callsBefore = mockService.callCounter
        var events = [ProviderEvent]()
        var seenReconciling = false
        let rateLimitedReconcile = expectation(description: "Rate-limited context change settles")
        api.observe().sink { event in
            // Skip the status replay sent to new subscribers; keep everything after.
            if !seenReconciling, event == .stale() || event == .ready() {
                return
            }
            events.append(event)
            if event == .reconciling() {
                seenReconciling = true
            }
            if seenReconciling, event == .stale() || event == .contextChanged() || event == .error(nil) {
                rateLimitedReconcile.fulfill()
            }
        }.store(in: &cancellables)

        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "second-context"))
        await fulfillment(of: [rateLimitedReconcile], timeout: 3)

        XCTAssertEqual(callsBefore, mockService.callCounter,
                       "A rate-limited reconcile must not hit the API.")
        XCTAssertEqual([.reconciling(), .stale()], events,
                       "Rate-limited onContextSet must emit .stale, not .contextChanged.")
        XCTAssertEqual(ProviderStatus.stale, api.getProviderStatus())
    }

    func testShouldFallBackOnTheGlobalSDKLoggerWhenNoneIsProvidedForTheEvaluation() async {
        let globalLogs = CapturingLogHandler.Store()
        OpenFeatureAPI.shared.setLogger(CapturingLogHandler.logger(label: "test.global", store: globalLogs))
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        // The 3 arguments overload is the one the SDK calls when it has no logger to pass.
        XCTAssertThrowsError(try provider.getBooleanEvaluation(
            key: "does-not-exist", defaultValue: false, context: defaultEvaluationContext))

        XCTAssertTrue(globalLogs.messages.contains("no flag found in cache for the key does-not-exist"),
                      "The provider should fall back on the logger set on the SDK, "
                      + "got: \(globalLogs.messages)")
    }

    func testShouldPreferTheLoggerOfTheEvaluationOverTheGlobalSDKOne() async {
        let globalLogs = CapturingLogHandler.Store()
        let sdkLogs = CapturingLogHandler.Store()
        OpenFeatureAPI.shared.setLogger(CapturingLogHandler.logger(label: "test.global", store: globalLogs))
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        api.setLogger(CapturingLogHandler.logger(label: "test.sdk", store: sdkLogs))
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        _ = api.getClient().getBooleanDetails(key: "does-not-exist", defaultValue: false)

        let expectedLog = "no flag found in cache for the key does-not-exist"
        XCTAssertTrue(sdkLogs.messages.contains(expectedLog),
                      "The logger given by the SDK for this evaluation should be used, "
                      + "got: \(sdkLogs.messages)")
        XCTAssertFalse(globalLogs.messages.contains(expectedLog),
                       "The global logger should not be used when the SDK provides one for the evaluation.")
    }
}

/// Collects the messages it receives, so that a test can assert on which logger the provider used.
struct CapturingLogHandler: LogHandler {
    final class Store {
        private let lock = NSLock()
        private var storedMessages: [String] = []

        var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storedMessages
        }

        func append(_ message: String) {
            lock.lock()
            defer { lock.unlock() }
            storedMessages.append(message)
        }
    }

    /// The provider logs its diagnostics at the debug level, which the default log level hides.
    static func logger(label: String, store: Store) -> Logger {
        return Logger(label: label) { _ in CapturingLogHandler(store: store) }
    }

    let store: Store
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .debug

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
             source: String, file: String, function: String, line: UInt) {
        store.append("\(message)")
    }
}
