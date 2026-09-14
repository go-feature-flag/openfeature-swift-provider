import XCTest
import Foundation
import OpenFeature
import OFREP
@testable import GOFeatureFlag

/// The tracking API of the SDK forwards to `GoFeatureFlagProvider.track`, which buffers the event
/// in the data collector. These tests drive the whole path and assert on what is really sent to
/// the `/v1/data/collector` endpoint.
class TrackingTests: XCTestCase {
    override func tearDown() {
        // OpenFeatureAPI.shared is global state, do not leak a logger to the other tests.
        OpenFeatureAPI.shared.setLogger(nil)
        super.tearDown()
    }

    func testShouldSendATrackingEventWithItsDetails() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(
                targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0",
                structure: ImmutableStructure(attributes: ["company": Value.string("GO Feature Flag")])))

        api.getClient().track(
            key: "cart-checkout",
            details: ImmutableTrackingEventDetails(
                value: 99.99, structure: ImmutableStructure(attributes: ["currency": Value.string("EUR")])))

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual("tracking", event.kind)
        XCTAssertEqual("cart-checkout", event.key)
        XCTAssertEqual("user", event.contextKind)
        XCTAssertEqual("ede04e44-463d-40d1-8fc0-b1d6855578d0", event.userKey)
        XCTAssertGreaterThan(event.creationDate, 0)
        XCTAssertEqual(
            [
                "targetingKey": JSONValue.string("ede04e44-463d-40d1-8fc0-b1d6855578d0"),
                "company": JSONValue.string("GO Feature Flag")
            ],
            event.evaluationContext)
        XCTAssertEqual(
            ["currency": JSONValue.string("EUR"), "value": JSONValue.double(99.99)],
            event.trackingEventDetails,
            "The numeric value of the details is sent as the `value` field, as the other providers do.")
    }

    func testShouldSendATrackingEventWithoutDetails() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0"))

        api.getClient().track(key: "page-visited")

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual("page-visited", event.key)
        XCTAssertEqual([:], event.trackingEventDetails)
    }

    func testShouldReportAnAnonymousUser() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(
                targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0",
                structure: ImmutableStructure(attributes: ["anonymous": Value.boolean(true)])))

        api.getClient().track(key: "page-visited")

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual("anonymousUser", event.contextKind)
    }

    func testShouldUseAPlaceholderWhenThereIsNoTargetingKey() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService), initialContext: ImmutableContext(targetingKey: ""))

        api.getClient().track(key: "page-visited")

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual("undefined-targetingKey", event.userKey)
        XCTAssertEqual([:], event.evaluationContext, "An empty targeting key is not worth sending.")
    }

    func testShouldSendTrackingAndFeatureEventsInTheSameBatch() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0"))

        let client = api.getClient()
        _ = client.getBooleanDetails(key: "my-flag", defaultValue: false)
        client.track(key: "cart-checkout")

        await waitForDataCollectorEvents(mockNetworkService, count: 2)
        let events = try collectedEvents(mockNetworkService)

        XCTAssertEqual(
            ["feature", "tracking"],
            events.map {
                switch $0 {
                case .feature(let event): return event.kind
                case .tracking(let event): return event.kind
                }
            }.sorted())
    }

    func testShouldIgnoreTrackingWhenTheDataCollectorIsDisabled() async throws {
        let logs = CapturingLogHandler.Store()
        OpenFeatureAPI.shared.setLogger(CapturingLogHandler.logger(label: "test.tracking", store: logs))
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService, dataFlushInterval: 0),
            initialContext: ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0"))

        api.getClient().track(key: "cart-checkout")
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(0, mockNetworkService.dataCollectorCallCounter)
        XCTAssertEqual(
            ["tracking event cart-checkout ignored: the data collector is disabled (dataFlushInterval is 0)"],
            logs.messages)
    }

    private func provider(
        _ mockNetworkService: MockNetworkingService,
        dataFlushInterval: TimeInterval = 1
    ) -> GoFeatureFlagProvider {
        return GoFeatureFlagProvider(
            options: GoFeatureFlagProviderOptions(
                endpoint: "https://localhost:1031",
                dataFlushInterval: dataFlushInterval,
                networkService: mockNetworkService))
    }

    private func trackingEvents(
        _ mock: MockNetworkingService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [TrackingEvent] {
        let events = (try? collectedEvents(mock, file: file, line: line)) ?? []
        return events.compactMap {
            guard case .tracking(let event) = $0 else { return nil }
            return event
        }
    }

    /// Every event of every data collector request recorded by the mock: which flush carries the
    /// event depends on where the timer happens to split the batch.
    private func collectedEvents(
        _ mock: MockNetworkingService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [CollectorEvent] {
        let bodies = mock.requests
            .filter { $0.url?.absoluteString.contains("/v1/data/collector") ?? false }
            .compactMap { $0.httpBody }
        XCTAssertFalse(bodies.isEmpty, "no data collector request recorded", file: file, line: line)
        return try bodies.flatMap { try JSONDecoder().decode(DataCollectorRequest.self, from: $0).events ?? [] }
    }

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
}
