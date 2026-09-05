import XCTest
import Foundation
// HookContext has no public initializer, building one requires the testable import.
@testable import OpenFeature
@testable import OFREP
@testable import GOFeatureFlag

/// The SDK dispatches a hook only for the flag type it declares (`supportsFlagValueType`), so the
/// guards protecting the data collector hooks against a value of another type can only be reached
/// by calling them directly, which is what these tests do.
class DataCollectorHooksTests: XCTestCase {
    private var logs: CapturingLogHandler.Store!
    private var manager: DataCollectorManager!

    override func setUp() {
        super.setUp()
        logs = CapturingLogHandler.Store()
        OpenFeatureAPI.shared.setLogger(CapturingLogHandler.logger(label: "test.hooks", store: logs))
        let mockNetworkService = MockNetworkingService(mockStatus: 200)
        let options = GoFeatureFlagProviderOptions(
            endpoint: "https://localhost:1031",
            networkService: mockNetworkService
        )
        manager = DataCollectorManager(
            goffAPI: GoFeatureFlagAPI(networkingService: mockNetworkService, options: options),
            options: options
        )
    }

    override func tearDown() {
        // OpenFeatureAPI.shared is global state, do not leak a logger to the other tests.
        OpenFeatureAPI.shared.setLogger(nil)
        manager = nil
        logs = nil
        super.tearDown()
    }

    func testShouldRecordAnEventWhenTheEvaluationHasTheTypeOfTheHook() {
        BooleanHook(dataCollectorMngr: manager).after(
            ctx: hookContext(defaultValue: false, type: .boolean, flagKey: "bool-flag"),
            details: FlagEvaluationDetails(flagKey: "bool-flag", value: true, variant: "variantA"),
            hints: [:])
        StringHook(dataCollectorMngr: manager).after(
            ctx: hookContext(defaultValue: "default", type: .string, flagKey: "string-flag"),
            details: FlagEvaluationDetails(flagKey: "string-flag", value: "1234value", variant: "variantA"),
            hints: [:])
        IntegerHook(dataCollectorMngr: manager).after(
            ctx: hookContext(defaultValue: Int64(1), type: .integer, flagKey: "int-flag"),
            details: FlagEvaluationDetails(flagKey: "int-flag", value: Int64(1234), variant: "variantA"),
            hints: [:])
        DoubleHook(dataCollectorMngr: manager).after(
            ctx: hookContext(defaultValue: 1.0, type: .double, flagKey: "double-flag"),
            details: FlagEvaluationDetails(flagKey: "double-flag", value: 12.34, variant: "variantA"),
            hints: [:])
        ObjectHook(dataCollectorMngr: manager).after(
            ctx: hookContext(defaultValue: Value.null, type: .object, flagKey: "object-flag"),
            details: FlagEvaluationDetails(
                flagKey: "object-flag", value: Value.structure(["toto": Value.integer(1234)]),
                variant: "variantA"),
            hints: [:])

        let events = recordedEvents()
        XCTAssertEqual(
            ["bool-flag", "double-flag", "int-flag", "object-flag", "string-flag"],
            events.map { $0.key }.sorted())
        XCTAssertTrue(events.allSatisfy { $0.kind == "feature" }, "Every event is a feature event.")
        XCTAssertTrue(events.allSatisfy { $0.contextKind == "user" })
        XCTAssertTrue(events.allSatisfy { $0.userKey == "ede04e44-463d-40d1-8fc0-b1d6855578d0" })
        XCTAssertTrue(events.allSatisfy { $0.variation == "variantA" })
        XCTAssertTrue(events.allSatisfy { $0.source == "PROVIDER_CACHE" })
        XCTAssertTrue(events.allSatisfy { $0.default == false },
                      "The evaluation succeeded, so the default value was not used.")
    }

    func testShouldRecordTheDefaultValueWhenTheEvaluationOfTheTypeOfTheHookFails() {
        let error = OpenFeatureError.flagNotFoundError(key: "bool-flag")
        BooleanHook(dataCollectorMngr: manager).error(
            ctx: hookContext(defaultValue: true, type: .boolean, flagKey: "bool-flag"),
            error: error, hints: [:])
        StringHook(dataCollectorMngr: manager).error(
            ctx: hookContext(defaultValue: "default", type: .string, flagKey: "string-flag"),
            error: error, hints: [:])
        IntegerHook(dataCollectorMngr: manager).error(
            ctx: hookContext(defaultValue: Int64(1), type: .integer, flagKey: "int-flag"),
            error: error, hints: [:])
        DoubleHook(dataCollectorMngr: manager).error(
            ctx: hookContext(defaultValue: 1.0, type: .double, flagKey: "double-flag"),
            error: error, hints: [:])
        ObjectHook(dataCollectorMngr: manager).error(
            ctx: hookContext(defaultValue: Value.null, type: .object, flagKey: "object-flag"),
            error: error, hints: [:])

        let events = recordedEvents()
        XCTAssertEqual(
            ["bool-flag", "double-flag", "int-flag", "object-flag", "string-flag"],
            events.map { $0.key }.sorted())
        XCTAssertTrue(events.allSatisfy { $0.variation == "SdkDefault" },
                      "There is no variant to report when the evaluation failed.")
        XCTAssertTrue(events.allSatisfy { $0.default == true },
                      "The value reported is the default one passed to the evaluation.")
    }

    func testShouldIgnoreAnEvaluationOfAnotherTypeAfterTheEvaluation() {
        // Every hook but StringHook receives a String evaluation, StringHook receives a Bool one.
        let stringCtx = hookContext(defaultValue: "a string", type: .string)
        let stringDetails = FlagEvaluationDetails(flagKey: "my-flag", value: "a string", variant: "variantA")

        BooleanHook(dataCollectorMngr: manager).after(ctx: stringCtx, details: stringDetails, hints: [:])
        IntegerHook(dataCollectorMngr: manager).after(ctx: stringCtx, details: stringDetails, hints: [:])
        DoubleHook(dataCollectorMngr: manager).after(ctx: stringCtx, details: stringDetails, hints: [:])
        ObjectHook(dataCollectorMngr: manager).after(ctx: stringCtx, details: stringDetails, hints: [:])
        StringHook(dataCollectorMngr: manager).after(
            ctx: hookContext(defaultValue: true, type: .boolean),
            details: FlagEvaluationDetails(flagKey: "my-flag", value: true, variant: "variantA"),
            hints: [:])

        XCTAssertEqual([], recordedEvents().map { $0.key },
                       "A value of another type cannot be reported, it must be dropped.")
        XCTAssertEqual(expectedWarnings, logs.messages.sorted())
    }

    func testShouldIgnoreAnEvaluationOfAnotherTypeOnAnError() {
        let error = OpenFeatureError.flagNotFoundError(key: "my-flag")
        let stringCtx = hookContext(defaultValue: "a string", type: .string)

        BooleanHook(dataCollectorMngr: manager).error(ctx: stringCtx, error: error, hints: [:])
        IntegerHook(dataCollectorMngr: manager).error(ctx: stringCtx, error: error, hints: [:])
        DoubleHook(dataCollectorMngr: manager).error(ctx: stringCtx, error: error, hints: [:])
        ObjectHook(dataCollectorMngr: manager).error(ctx: stringCtx, error: error, hints: [:])
        StringHook(dataCollectorMngr: manager).error(
            ctx: hookContext(defaultValue: true, type: .boolean), error: error, hints: [:])

        XCTAssertEqual([], recordedEvents().map { $0.key },
                       "A default value of another type cannot be reported, it must be dropped.")
        XCTAssertEqual(expectedWarnings, logs.messages.sorted())
    }

    private let expectedWarnings = [
        "Default value is not of type Bool",
        "Default value is not of type Double",
        "Default value is not of type Integer",
        "Default value is not of type Object",
        "Default value is not of type String"
    ]

    private func hookContext<T>(
        defaultValue: T,
        type: FlagValueType,
        flagKey: String = "my-flag"
    ) -> HookContext<T> {
        return HookContext(
            flagKey: flagKey,
            type: type,
            defaultValue: defaultValue,
            ctx: ImmutableContext(targetingKey: "ede04e44-463d-40d1-8fc0-b1d6855578d0"),
            clientMetadata: nil,
            providerMetadata: nil)
    }

    /// Reads the buffer of the manager through its own queue: `appendFeatureEvent` writes to it
    /// behind a barrier, so reading `events` directly would race with it.
    private func recordedEvents() -> [FeatureEvent] {
        return manager.queue.sync(flags: .barrier) { manager.events }
    }
}
