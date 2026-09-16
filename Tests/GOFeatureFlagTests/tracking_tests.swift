import XCTest
import Foundation
import OpenFeature
import OFREP
@testable import GOFeatureFlag
import TestSupport

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

    func testShouldSendTrackingAndFeatureEventsInTheSameBuffer() async throws {
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

        // `CapturingLogHandler` is installed on `OpenFeatureAPI.shared`, which OFREP also logs to,
        // so assert that the message is present rather than that it is the only one.
        let expected =
            "tracking event cart-checkout ignored: the data collector is disabled (dataFlushInterval is 0)"
        await waitFor(timeout: 5.0) { logs.messages.contains(expected) }
        XCTAssertTrue(
            logs.messages.contains(expected),
            "expected the disabled data collector warning, got \(logs.messages)")
        XCTAssertEqual(0, mockNetworkService.dataCollectorCallCounter)
    }

    func testShouldSendATrackingEventWithoutAnyEvaluationContext() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: provider(mockNetworkService))

        api.getClient().track(key: "page-visited")

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual("page-visited", event.key)
        XCTAssertEqual("undefined-targetingKey", event.userKey)
        XCTAssertEqual("user", event.contextKind)
        XCTAssertEqual([:], event.evaluationContext)
        XCTAssertEqual([:], event.trackingEventDetails)
    }

    func testShouldSendNonScalarContextAndDetailsAttributes() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        // `Value.date` is deliberately not in the evaluation context: the OFREP bulk evaluation
        // request serializes the context with `JSONSerialization`, which cannot encode a `Date`
        // and traps the process. Tracking details take the `JSONValue` path and are unaffected.
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(
                targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0",
                structure: ImmutableStructure(attributes: [
                    "roles": Value.list([Value.string("admin"), Value.string("beta")]),
                    "address": Value.structure(["city": Value.string("Paris")])
                ])))

        api.getClient().track(
            key: "cart-checkout",
            details: ImmutableTrackingEventDetails(
                structure: ImmutableStructure(attributes: [
                    "items": Value.list([Value.string("book"), Value.integer(3)]),
                    "shipping": Value.structure(["express": Value.boolean(true)]),
                    "orderedAt": Value.date(date)
                ])))

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual(
            JSONValue.array([.string("admin"), .string("beta")]), event.evaluationContext["roles"])
        XCTAssertEqual(
            JSONValue.object(["city": .string("Paris")]), event.evaluationContext["address"])
        XCTAssertEqual(
            JSONValue.array([.string("book"), .integer(3)]), event.trackingEventDetails["items"])
        // `Value.date` is exported through `toJSONValue()` as a time interval since the reference
        // date, not since the Unix epoch. Pinned here so a change to that mapping is deliberate.
        XCTAssertEqual(
            date.timeIntervalSinceReferenceDate,
            try XCTUnwrap(numeric(event.trackingEventDetails["orderedAt"])),
            accuracy: 0.0001)
        XCTAssertEqual(
            JSONValue.object(["express": .bool(true)]), event.trackingEventDetails["shipping"])
    }

    func testShouldLetTheTypedValueWinOverACustomAttributeNamedValue() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0"))

        api.getClient().track(
            key: "cart-checkout",
            details: ImmutableTrackingEventDetails(
                value: 12.5, structure: ImmutableStructure(attributes: ["value": Value.string("ignored")])))

        await waitForDataCollectorEvents(mockNetworkService, count: 1)
        let event = try XCTUnwrap(trackingEvents(mockNetworkService).first)

        XCTAssertEqual(
            ["value": JSONValue.double(12.5)],
            event.trackingEventDetails,
            "The numeric value of the details wins over a custom attribute of the same name.")
    }

    /// The field names are the contract with the relay proxy data collector: they have to keep
    /// matching the JSON tags of the `exporter.TrackingEvent` Go struct. `collectedEvents` decodes
    /// through `TrackingEvent` itself, so it cannot catch a rename, this asserts on the raw body.
    func testShouldSendTheFieldNamesExpectedByTheRelayProxy() async throws {
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(
            provider: provider(mockNetworkService),
            initialContext: ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0"))

        api.getClient().track(
            key: "cart-checkout",
            details: ImmutableTrackingEventDetails(
                value: 99.99, structure: ImmutableStructure(attributes: ["currency": Value.string("EUR")])))

        await waitForDataCollectorEvents(mockNetworkService, count: 1)

        let body = try XCTUnwrap(
            mockNetworkService.requests
                .filter { $0.url?.absoluteString.contains("/v1/data/collector") ?? false }
                .compactMap { $0.httpBody }
                .first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        let event = try XCTUnwrap(events.first { $0["kind"] as? String == "tracking" })

        XCTAssertEqual(
            ["kind", "contextKind", "userKey", "creationDate", "key", "evaluationContext",
             "trackingEventDetails"].sorted(),
            event.keys.sorted())
        XCTAssertEqual("cart-checkout", event["key"] as? String)
        XCTAssertEqual("user", event["contextKind"] as? String)
        XCTAssertEqual("ede04e44-463d-40d1-8fc0-b1d6855578d0", event["userKey"] as? String)
        XCTAssertEqual(
            99.99,
            try XCTUnwrap((event["trackingEventDetails"] as? [String: Any])?["value"] as? Double),
            accuracy: 0.0001)
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

    /// `JSONValue.init(from:)` tries `Int64` before `Double`, so a whole number always decodes
    /// back as `.integer` whichever case was encoded. Compare numbers, not cases.
    private func numeric(_ value: JSONValue?) -> Double? {
        switch value {
        case .integer(let int64): return Double(int64)
        case .double(let double): return double
        default: return nil
        }
    }

    /// Polls `condition` instead of sleeping for a fixed duration.
    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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
