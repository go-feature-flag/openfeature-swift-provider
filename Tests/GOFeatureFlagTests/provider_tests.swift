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
        let evaluationCtx = ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        XCTAssertEqual(api.getProviderStatus(), ProviderStatus.ready)
        
        
        let client = api.getClient()
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)
        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        await waitForDataCollectorEvents(mockNetworkService, count: 6)

        // How many flushes it takes depends on where the 1s timer happens to
        // split the batch, so assert on the event total, not the call count.
        XCTAssertGreaterThanOrEqual(mockNetworkService.dataCollectorCallCounter, 1)
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
        let evaluationCtx = ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)
        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        await waitForDataCollectorEvents(mockNetworkService, count: 6)

        XCTAssertGreaterThanOrEqual(mockNetworkService.dataCollectorCallCounter, 1)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
        
        do {
            let httpBodyCollector = try lastDataCollectorBody(mockNetworkService)
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
    
    func testExporterMetadataNil() async {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let provider = GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                dataFlushInterval: 1,
                exporterMetadata: nil,
                networkService: mockNetworkService
            )
        )
        let evaluationCtx = ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)
        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        await waitForDataCollectorEvents(mockNetworkService, count: 6)

        XCTAssertGreaterThanOrEqual(mockNetworkService.dataCollectorCallCounter, 1)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
        
        do {
            let httpBodyCollector = try lastDataCollectorBody(mockNetworkService)
            let decodedStruct = try JSONDecoder().decode(DataCollectorRequest.self, from: httpBodyCollector)
            let want = [
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
        let evaluationCtx = ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag", defaultValue: 1)

        await waitForDataCollectorEvents(mockNetworkService, count: 3)

        // Whether the 3 events land in one flush or two depends on where the
        // timer boundary falls, so record the count and assert it grows.
        let callsAfterFirstBatch = mockNetworkService.dataCollectorCallCounter
        XCTAssertGreaterThanOrEqual(callsAfterFirstBatch, 1)
        XCTAssertEqual(3, mockNetworkService.dataCollectorEventCounter)

        _ = client.getDoubleDetails(key: "double-flag", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag", defaultValue: Value.null)

        await waitForDataCollectorEvents(mockNetworkService, count: 6)

        XCTAssertGreaterThan(mockNetworkService.dataCollectorCallCounter, callsAfterFirstBatch)
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
        let evaluationCtx = ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag-error", defaultValue: false)
        _ = client.getBooleanDetails(key: "my-flag-error", defaultValue: false)
        _ = client.getIntegerDetails(key: "int-flag-error", defaultValue: 1)

        await waitForDataCollectorEvents(mockNetworkService, count: 3)

        let callsAfterFirstBatch = mockNetworkService.dataCollectorCallCounter
        XCTAssertGreaterThanOrEqual(callsAfterFirstBatch, 1)
        XCTAssertEqual(3, mockNetworkService.dataCollectorEventCounter)

        _ = client.getDoubleDetails(key: "double-flag-error", defaultValue: 1.0)
        _ = client.getStringDetails(key: "string-flag-error", defaultValue: "default")
        _ = client.getObjectDetails(key: "object-flag-error", defaultValue: Value.list([]))

        await waitForDataCollectorEvents(mockNetworkService, count: 6)

        XCTAssertGreaterThan(mockNetworkService.dataCollectorCallCounter, callsAfterFirstBatch)
        XCTAssertEqual(6, mockNetworkService.dataCollectorEventCounter)
    }

    func testProviderCustomHeaders() async {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let provider = GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                apiKey: "apiKey1",
                customHeaders: [
                    "X-Custom-Header": "custom-value",
                    "Authorization": "Bearer custom" // should be overwritten by apiKey
                ],
                networkService: mockNetworkService
            )
        )
        let evaluationCtx = ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider, initialContext: evaluationCtx)
        let client = api.getClient()

        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)

        guard let request = mockNetworkService.requests.last else {
            XCTFail("No request captured")
            return
        }

        XCTAssertEqual("custom-value", request.allHTTPHeaderFields?["X-Custom-Header"])
        XCTAssertEqual("Bearer apiKey1", request.allHTTPHeaderFields?["Authorization"])
    }
  
    /// Polls until the mock has recorded `count` data collector events, instead
    /// of sleeping a fixed interval and hoping the flush already landed.
    /// The events are recorded asynchronously by a background flush timer, so a
    /// fixed wait made these tests fail intermittently on loaded CI runners.
    private func waitForDataCollectorEvents(
        _ mock: MockNetworkingService,
        count: Int,
        timeout: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if mock.dataCollectorEventCounter >= count {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail(
            "timed out after \(timeout)s waiting for \(count) data collector events, "
            + "got \(mock.dataCollectorEventCounter)",
            file: file,
            line: line
        )
    }

    /// Returns the body of the most recent data collector request.
    /// Picking `requests.last` is wrong: the provider also polls for flags, so
    /// a bulk evaluation request can land after the flush we care about.
    private func lastDataCollectorBody(
        _ mock: MockNetworkingService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Data {
        let collectorRequests = mock.requests.filter {
            $0.url?.absoluteString.contains("/v1/data/collector") ?? false
        }
        let body = collectorRequests.last?.httpBody
        return try XCTUnwrap(body, "no data collector request recorded", file: file, line: line)
    }
}
