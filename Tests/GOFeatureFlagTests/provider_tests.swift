import XCTest
import Combine
import Foundation
import OpenFeature
@testable import GOFeatureFlag

class GoFeatureFlagProviderTests: XCTestCase {
    func testProviderMetadataName() async {
        let options = GoFeatureFlagProviderOptions(endpoint: "https://localhost:1031")
        let provider = GoFeatureFlagProvider(options: options)
        XCTAssertEqual(provider.metadata.name, "GO Feature Flag provider")
    }

    func testProviderValidHook() async {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let provider = GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                dataFlushInterval: 1,
                networkService: mockNetworkService
            )
        )
        let evaluationCtx = MutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)
        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        let expectation = self.expectation(description: "Waiting for delay")

        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertEqual(1, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
    }
    
    func testExporterMetadata() async {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let provider = GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                dataFlushInterval: 1,
                exporterMetadata: ["version": ExporterMetadataValue.string("1.0.0"),"testInt": ExporterMetadataValue.integer(123), "testDouble": ExporterMetadataValue.double(123.45)],
                networkService: mockNetworkService
            )
        )
        let evaluationCtx = MutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)
        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        let expectation = self.expectation(description: "Waiting for delay")

        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertEqual(1, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
        
        do {
            let httpBodyCollector = mockNetworkService.requests[mockNetworkService.requests.count - 1].httpBody!
            let decodedStruct = try JSONDecoder().decode(DataCollectorRequest.self, from: httpBodyCollector)
            let want = [
                "version": ExporterMetadataValue.string("1.0.0"),
                "testDouble": ExporterMetadataValue.double(123.45),
                "testInt": ExporterMetadataValue.integer(123),
                "openfeature": ExporterMetadataValue.bool(true),
                "provider": ExporterMetadataValue.string("swift")
            ] as? [String: ExporterMetadataValue]
            XCTAssertEqual(want, decodedStruct.meta)
        } catch {
            XCTFail("Error deserializing: \(error)")
        }
        
    }

    func testProviderMultipleHookCall() async {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let provider = GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                dataFlushInterval: 2,
                networkService: mockNetworkService
            )
        )
        let evaluationCtx = MutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)

        let expectation = self.expectation(description: "Waiting for delay")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 4.0)

        XCTAssertEqual(1, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(3, mockNetworkService.dataCollectorEventCounter)

        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        let expectation2 = self.expectation(description: "Waiting for delay")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { expectation2.fulfill() }
        await fulfillment(of: [expectation2], timeout: 4.0)

        XCTAssertEqual(2, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
    }

    func testProviderMultipleHookCallWithErrors() async {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let provider = GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                dataFlushInterval: 2,
                networkService: mockNetworkService
            )
        )
        let evaluationCtx = MutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag-error", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag-error", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag-error", defaultValue: 1)

        let expectation = self.expectation(description: "Waiting for delay")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 4.0)

        XCTAssertEqual(1, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(3, mockNetworkService.dataCollectorEventCounter)

        _ = client.getDoubleDetails(key: "double-flag-error", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag-error", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag-error", defaultValue: Value.list([]))

        let expectation2 = self.expectation(description: "Waiting for delay")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { expectation2.fulfill() }
        await fulfillment(of: [expectation2], timeout: 4.0)

        XCTAssertEqual(2, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
    }
}
