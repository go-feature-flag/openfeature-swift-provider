import XCTest
import Combine
import Foundation
import OpenFeature
@testable import OFREP

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
            if(event != ProviderEvent.error(errorCode: nil, message: "The operation couldn’t be completed. (OFREP.OfrepError error 3.)")){
                XCTFail("If OFREP API returns a 429 we should receive an ERROR event, received: \(event)")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3.0)
        cancellable.cancel()
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
            if(event != ProviderEvent.error(errorCode: nil, message: "The operation couldn’t be completed. (OpenFeature.OpenFeatureError error 5.)")){
                XCTFail("If OFREP API returns a 400 for TARGETING_KEY_MISSING we should receive an ERROR event, received: \(event)")
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
            if(event != ProviderEvent.error(errorCode: nil, message: "The operation couldn’t be completed. (OpenFeature.OpenFeatureError error 4.)")){
                XCTFail("If OFREP API returns a 400 for INVALID_CONTEXT we should receive an ERROR event, received: \(event)")
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
            if(event != ProviderEvent.error(errorCode: nil, message: "The operation couldn’t be completed. (OpenFeature.OpenFeatureError error 2.)")){
                XCTFail("If OFREP API returns a 400 for PARSE_ERROR we should receive an ERROR event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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

        let newContext = MutableContext()
        newContext.setTargetingKey(targetingKey: "second-context")
        newContext.add(key: "email", value: Value.string("batman@gofeatureflag.org"))

        let expectation1 = expectation(description: "event 1")
        let expectation2 = expectation(description: "event 2")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            receivedEvents.append(event!)
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
        let expectedEvents: [ProviderEvent] = [.reconciling, .contextChanged]
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

        let ctx = MutableContext()
        ctx.setTargetingKey(targetingKey: "429")

    
        let expectation1 = expectation(description: "Ready event")
        let expectation2 = expectation(description: "Stale event")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            receivedEvents.append(event!)
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

        let options = OfrepProviderOptions(
            endpoint: "http://localhost:1031/",
            pollInterval: 1,
            networkService: mockService)
        let provider = OfrepProvider(options: options)
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

        let expectation1 = expectation(description: "ConfigurationChanged event")
        var receivedEvents = [ProviderEvent]()
        api.observe().sink{ event in
            receivedEvents.append(event!)
            switch receivedEvents.count{
            case 1:
                expectation1.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        await fulfillment(of:[expectation1], timeout: 5)
        let expectedEvents: [ProviderEvent] = [.configurationChanged]
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
            }
            expectation.fulfill()
        }
        await api.setProviderAndWait(provider: provider, initialContext: defaultEvaluationContext)
        await fulfillment(of: [expectation], timeout: 3)

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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
            if(event != ProviderEvent.ready){
                XCTFail("If OFREP API returns a 200 we should receive a ready event, received: \(event)")
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
}
