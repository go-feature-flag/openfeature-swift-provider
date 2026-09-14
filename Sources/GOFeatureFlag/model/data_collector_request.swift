import Foundation

struct DataCollectorRequest: Codable {
    var meta: [String:ExporterMetadataValue]?
    var events: [CollectorEvent]? = []

    public init(meta: [String:ExporterMetadataValue]? = [:], events: [CollectorEvent]? = []) {
        self.meta = meta
        self.events = events
    }
}
