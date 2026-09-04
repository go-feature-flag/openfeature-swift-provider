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
    func testShouldEvaluateEveryTypeWithoutALogger() async throws {
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        // The 3 arguments overloads are the ones a caller uses directly: the SDK always calls the
        // 4 arguments ones to pass the logger of the evaluation.
        let boolEval = try provider.getBooleanEvaluation(
            key: "bool-flag", defaultValue: false, context: defaultEvaluationContext)
        XCTAssertEqual(true, boolEval.value)

        let stringEval = try provider.getStringEvaluation(
            key: "string-flag", defaultValue: "default", context: defaultEvaluationContext)
        XCTAssertEqual("1234value", stringEval.value)

        let intEval = try provider.getIntegerEvaluation(
            key: "int-flag", defaultValue: 1, context: defaultEvaluationContext)
        XCTAssertEqual(1234, intEval.value)

        let doubleEval = try provider.getDoubleEvaluation(
            key: "double-flag", defaultValue: 1.0, context: defaultEvaluationContext)
        XCTAssertEqual(12.34, doubleEval.value)

        let objectEval = try provider.getObjectEvaluation(
            key: "object-flag", defaultValue: Value.null, context: defaultEvaluationContext)
        XCTAssertEqual(
            Value.structure(["testValue": Value.structure(["toto": Value.integer(1234)])]),
            objectEval.value)
    }

    func testShouldEmitAFatalErrorWhenAContextChangeIsUnauthorized() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        var receivedEvents = [ProviderEvent]()
        let errorReceived = expectation(description: "The rejected context change reports an error")
        api.observe().sink { event in
            if event == .ready() {
                return // replay of the current status for a new subscriber
            }
            receivedEvents.append(event)
            if case .error = event {
                errorReceived.fulfill()
            }
        }.store(in: &cancellables)

        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "401-after-first"))
        await fulfillment(of: [errorReceived], timeout: 3)

        XCTAssertEqual(.reconciling(), receivedEvents.first)
        guard case .error(let details) = receivedEvents.last else {
            return XCTFail("expected an error event, got \(String(describing: receivedEvents.last))")
        }
        XCTAssertEqual(ErrorCode.providerFatal, details?.errorCode,
                       "A 401 on a context change is not recoverable, the provider has to report it as fatal.")
        XCTAssertEqual(ProviderStatus.fatal, provider.status)
    }

    func testShouldEmitAnErrorWhenTheAPIRejectsTheNewContext() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)

        var receivedEvents = [ProviderEvent]()
        let errorReceived = expectation(description: "The rejected context change reports an error")
        api.observe().sink { event in
            if event == .ready() {
                return // replay of the current status for a new subscriber
            }
            receivedEvents.append(event)
            if case .error = event {
                errorReceived.fulfill()
            }
        }.store(in: &cancellables)

        // Whether a context is usable is the answer of the API, not something the provider
        // decides on its own: here the server rejects the whole bulk evaluation.
        api.setEvaluationContext(evaluationContext: ImmutableContext(targetingKey: "error-after-first"))
        await fulfillment(of: [errorReceived], timeout: 3)

        XCTAssertEqual(
            [.reconciling(),
             .error(ProviderEventDetails(message: "Invalid or missing context", errorCode: .invalidContext))],
            receivedEvents)
        XCTAssertEqual(ProviderStatus.error, provider.status)
    }

    func testShouldMapAProviderNotReadyBulkErrorToTheMatchingError() async {
        let mockResponse = """
{
    "errorCode": "PROVIDER_NOT_READY",
    "errorDetails": "Error details about PROVIDER_NOT_READY"
}
"""
        let mockService = MockNetworkingService(mockData: mockResponse.data(using: .utf8), mockStatus: 400)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        var receivedEvents = [ProviderEvent]()
        let expectation = XCTestExpectation(description: "waiting for the error event")
        let cancellable = provider.observe().sink { event in
            receivedEvents.append(event)
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()

        XCTAssertEqual(
            [.error(ProviderEventDetails(
                message: "The value was resolved before the provider was ready",
                errorCode: .providerNotReady))],
            receivedEvents)
    }

    func testShouldMapAnUnhandledBulkErrorToAGeneralError() async {
        // FLAG_NOT_FOUND is a valid OFREP error code, but it makes no sense for a whole bulk
        // evaluation, so it falls back on a general error.
        let mockResponse = """
{
    "errorCode": "FLAG_NOT_FOUND",
    "errorDetails": "Error details about FLAG_NOT_FOUND"
}
"""
        let mockService = MockNetworkingService(mockData: mockResponse.data(using: .utf8), mockStatus: 400)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        var receivedEvents = [ProviderEvent]()
        let expectation = XCTestExpectation(description: "waiting for the error event")
        let cancellable = provider.observe().sink { event in
            receivedEvents.append(event)
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)
        cancellable.cancel()

        XCTAssertEqual(
            [.error(ProviderEventDetails(
                message: "General error: Error details about FLAG_NOT_FOUND",
                errorCode: .general))],
            receivedEvents)
    }

    func testShouldCallTheAPIAgainWhenA429HasNoRetryAfterHeader() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        var receivedEvents = [ProviderEvent]()
        let recovered = expectation(description: "Ready event after the 429")
        api.observe().sink { event in
            receivedEvents.append(event)
            if receivedEvents.count == 3 {
                recovered.fulfill()
            }
        }.store(in: &cancellables)

        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "429-no-retry-after"))
        await fulfillment(of: [recovered], timeout: 10)

        XCTAssertEqual([.ready(), .stale(), .ready()], Array(receivedEvents.prefix(3)),
                       "Without a Retry-After header there is no window to respect, "
                       + "so the next poll has to reach the API again.")
        XCTAssertGreaterThanOrEqual(mockService.callCounter, 3)
    }

    func testShouldRespectARetryAfterHeaderExpressedAsAnHTTPDate() async {
        let mockService = MockNetworkingService(mockStatus: 200)
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()

        var receivedEvents = [ProviderEvent]()
        let stale = expectation(description: "Stale event")
        api.observe().sink { event in
            receivedEvents.append(event)
            if receivedEvents.count == 2 {
                stale.fulfill()
            }
        }.store(in: &cancellables)

        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "429-http-date"))
        await fulfillment(of: [stale], timeout: 10)
        let callsWhenRateLimited = mockService.callCounter
        // Let a couple of poll intervals pass: the provider must not call the API again.
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertEqual([.ready(), .stale()], Array(receivedEvents.prefix(2)))
        XCTAssertEqual(callsWhenRateLimited, mockService.callCounter,
                       "A Retry-After given as an HTTP-date must be honoured like a delay in seconds.")
        XCTAssertEqual(ProviderStatus.stale, api.getProviderStatus())
    }

    func testShouldLogWhenPollingIsUnauthorized() async {
        let logs = CapturingLogHandler.Store()
        OpenFeatureAPI.shared.setLogger(CapturingLogHandler.logger(label: "test.polling", store: logs))
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "401-after-first"))

        let logged = await waitForLog(logs, containing: "error while polling the OFREP API")
        XCTAssertTrue(logged, "A poll rejected with a 401 should be logged, got: \(logs.messages)")
    }

    func testShouldLogWhenPollingReceivesAnErrorResponse() async {
        let logs = CapturingLogHandler.Store()
        OpenFeatureAPI.shared.setLogger(CapturingLogHandler.logger(label: "test.polling", store: logs))
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "error-after-first"))

        let logged = await waitForLog(logs, containing: "error while polling the OFREP API")
        XCTAssertTrue(logged,
                      "A poll rejected by the API itself should be logged, got: \(logs.messages)")
    }

    /// Polls until `store` has recorded a message containing `needle`, instead of sleeping a
    /// fixed interval and hoping the background poll already ran.
    private func waitForLog(
        _ store: CapturingLogHandler.Store,
        containing needle: String,
        timeout: TimeInterval = 10.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if store.messages.contains(where: { $0.contains(needle) }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// Polls `provider.status` until it reaches `target`, instead of sleeping a fixed interval and
    /// hoping the background poll already ran.
    private func waitForStatus(
        _ provider: OfrepProvider,
        equals target: ProviderStatus,
        timeout: TimeInterval = 10.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if provider.status == target {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    func testShouldRecoverToReadyWhenInitialisationFailsButPollingSucceeds() async {
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1, // polling must start even though the initial fetch fails
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider, initialContext: ImmutableContext(targetingKey: "fail-init-then-recover"))

        // The initial fetch failed with a 5xx, so the provider starts in error with an empty cache.
        XCTAssertEqual(api.getProviderStatus(), ProviderStatus.error)

        // Polling must still have started and must heal the provider once the API answers again.
        let recovered = await waitForStatus(provider, equals: .ready)
        XCTAssertTrue(recovered, "Polling should recover a failed initialisation to .ready")
        // The recovered cache must now serve flags.
        let evaluation = try? provider.getBooleanEvaluation(key: "my-flag", defaultValue: false, context: nil)
        XCTAssertEqual(evaluation?.value, true)
    }

    func testShouldNotLetASlowInitializeOverwriteASupersedingContextChange() async {
        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0, // isolate the init-vs-context race; no polling to also write the cache
            networkService: MockNetworkingService(mockStatus: 200))
        let provider = OfrepProvider(options: options)

        // Kick off a slow initialisation, then immediately supersede it with a context change whose
        // fetch is instant. Since 0.6.0 the SDK does not wait for initialize's Future before
        // dispatching onContextSet, so this is the real ordering.
        _ = provider.initialize(initialContext: ImmutableContext(targetingKey: "slow-context"))
        _ = provider.onContextSet(
            oldContext: nil, newContext: ImmutableContext(targetingKey: "second-context"))

        // Wait past the slow init fetch (500ms) so, unguarded, its response would have landed last.
        try? await Task.sleep(nanoseconds: 900_000_000)

        // The superseding context's flags must win: a cancelled initialize must not overwrite them.
        // "slow-context" resolves my-flag=true, "second-context" resolves my-flag=false.
        let evaluation = try? provider.getBooleanEvaluation(key: "my-flag", defaultValue: true, context: nil)
        XCTAssertEqual(evaluation?.value, false,
                       "A superseded initialize must not overwrite the new context's cached flags")
    }

    /// Hammers the synchronous flag reads from many OS threads while the polling timer and repeated
    /// context changes rewrite the shared cache and evaluation context concurrently. Meant to run
    /// under ThreadSanitizer (`swift test --sanitize=thread`): without the provider's state lock the
    /// unsynchronized `inMemoryCache` / `evaluationContext` accesses race and TSan aborts the test
    /// (the unguarded version can also crash intermittently on its own).
    func testConcurrentEvaluationAndBackgroundRefreshIsRaceFree() async {
        let provider = OfrepProvider(options: OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 0.01, // fire the polling timer constantly so it keeps rewriting the cache
            networkService: StressNetworkingService()))
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider, initialContext: ImmutableContext(targetingKey: "stress-0"))

        // Rewrite the evaluation context (which also triggers a reconcile that rewrites the cache)
        // on a background task, so the context read on the polling thread races the writes below.
        let contextChurn = Task {
            for iteration in 0..<150 {
                if Task.isCancelled { break }
                _ = provider.onContextSet(
                    oldContext: nil,
                    newContext: ImmutableContext(targetingKey: "stress-\(iteration)"))
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms between context changes
            }
        }

        // Many OS threads reading the cache at once, concurrent with the timer/reconcile writes.
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<2_000 {
                _ = try? provider.getBooleanEvaluation(key: "my-flag", defaultValue: false, context: nil)
                _ = try? provider.getStringEvaluation(key: "string-flag", defaultValue: "", context: nil)
            }
        }

        contextChurn.cancel()
        // Let the last in-flight reconcile / poll settle before the provider is torn down.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // The provider is still usable and consistent after the concurrent storm.
        let evaluation = try? provider.getBooleanEvaluation(key: "my-flag", defaultValue: false, context: nil)
        XCTAssertEqual(evaluation?.value, true)
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

/// A minimal networking stub for the concurrency stress test: every call returns a fresh 200 with a
/// brand-new ETag so every poll and reconcile writes the cache. It holds no shared mutable state
/// (the ETag is a fresh `UUID` per call), so overlapping requests add no ThreadSanitizer report of
/// the stub's own making.
final class StressNetworkingService: NetworkingService {
    func doRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["ETag": UUID().uuidString])!
        return (Self.body.data(using: .utf8)!, response)
    }

    private static let body = """
    {"flags":[
      {"value":true,"key":"my-flag","reason":"STATIC","variant":"variantA"},
      {"value":"1234value","key":"string-flag","reason":"STATIC","variant":"variantA"}
    ]}
    """
}
