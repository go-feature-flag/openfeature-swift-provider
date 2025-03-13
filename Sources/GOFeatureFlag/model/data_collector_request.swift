import Foundation

struct DataCollectorRequest: Codable {
    var meta: [String:ExporterMetadataValue]?
    var events: [FeatureEvent]? = []

    public init(meta: [String:ExporterMetadataValue]? = [:], events: [FeatureEvent]? = []) {
        self.meta = meta
        self.events = events
    }
}
