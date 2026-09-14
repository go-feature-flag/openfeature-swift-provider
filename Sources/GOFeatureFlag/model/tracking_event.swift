import Foundation
import OFREP

/// TrackingEvent is the representation of an event sent through the OpenFeature tracking API.
/// It is collected in the same buffer as the `FeatureEvent` and sent to the relay proxy data
/// collector endpoint.
///
/// Note: the relay proxy ingests tracking events since v1.45.0.
struct TrackingEvent: Codable {
    // Kind for a tracking event is tracking.
    var kind: String

    // ContextKind is the kind of context which generated an event.
    // This will only be "anonymousUser" for events generated on behalf of an anonymous user
    // or the reserved word "user" for events generated on behalf of a non-anonymous user.
    var contextKind: String

    // UserKey is the targeting key of the evaluation context associated to this event.
    var userKey: String

    // CreationDate is when the event has been created, at Unix epoch time in seconds.
    var creationDate: Int64

    // Key is the name of the tracking event.
    var key: String

    // EvaluationContext is the evaluation context used when the event was emitted.
    var evaluationContext: [String: JSONValue]

    // TrackingEventDetails is the data pertinent to this particular tracking event.
    var trackingEventDetails: [String: JSONValue]
}
