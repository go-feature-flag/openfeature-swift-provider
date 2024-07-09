import Foundation
import OFREP

struct FeatureEvent: Codable {
    // Kind for a feature event is feature.
    // A feature event will only be generated if the trackEvents attribute of the flag is set to true.
    var kind: String

    // ContextKind is the kind of context which generated an event.
    // This will only be "anonymousUser" for events generated on behalf of an anonymous user
    // or the reserved word "user" for events generated on behalf of a non-anonymous user
    var contextKind: String?

    // UserKey The key of the user object used in a feature flag evaluation.
    // Details for the user object used in a feature flag evaluation as reported by the "feature" event
    // are transmitted periodically with a separate index event.
    var userKey: String

    // CreationDate When the feature flag was requested at Unix epoch time in milliseconds.
    var creationDate: Int64

    // Key of the feature flag requested.
    var key: String

    // Variation of the flag requested. Flag variation values can be "True", "False", "Default" 
    // or "SdkDefault"
    // depending on which value was taken during flag evaluation.
    // "SdkDefault" is used when an error is detected and the default value passed during the 
    // call to your variation is used.
    var variation: String?

    // Value of the feature flag returned by feature flag evaluation.
    var value: JSONValue

    // Default value is set to true if feature flag evaluation failed,
    // in which case the value returned was the default value passed to variation.
    // If the default field is omitted, it is assumed to be false.
    var `default`: Bool

    // Version contains the version of the flag.
    // If the field is omitted for the flag in the configuration file the 
    // default version will be 0.
    var version: String?

    // Source indicates where the event was generated.
    // This is set to SERVER when the event was evaluated 
    // in the relay-proxy and PROVIDER_CACHE when it is evaluated from the cache.
    var source: String
}

// Helper struct to handle `Any` type JSON serialization/deserialization
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            self.value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            self.value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            self.value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            self.value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            self.value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            var dict: [String: Any] = [:]
            for (key, value) in dictValue {
                dict[key] = value.value
            }
            self.value = dict
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            let anyCodableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(anyCodableArray)
        } else if let dictValue = value as? [String: Any] {
            let anyCodableDict = dictValue.mapValues { AnyCodable($0) }
            try container.encode(anyCodableDict)
        } else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode value")
            )
        }
    }
}
