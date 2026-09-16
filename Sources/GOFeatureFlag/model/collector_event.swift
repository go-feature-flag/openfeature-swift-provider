import Foundation

/// CollectorEvent is the union of the event types accepted by the relay proxy data collector.
/// Both variants are serialized as plain JSON objects, without any discriminator wrapper, so the
/// payload stays identical to the one produced by the other GO Feature Flag providers.
enum CollectorEvent: Codable {
    case feature(FeatureEvent)
    case tracking(TrackingEvent)

    private enum DiscriminatorKeys: String, CodingKey {
        case kind
    }

    init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let kind = try discriminator.decode(String.self, forKey: .kind)
        let container = try decoder.singleValueContainer()
        switch kind {
        case "tracking":
            self = .tracking(try container.decode(TrackingEvent.self))
        default:
            self = .feature(try container.decode(FeatureEvent.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .feature(let event):
            try container.encode(event)
        case .tracking(let event):
            try container.encode(event)
        }
    }
}
