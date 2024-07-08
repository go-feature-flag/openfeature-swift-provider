import Foundation

struct DataCollectorRequest: Codable {
    var meta: [String:String]?
    var events: [FeatureEvent]? = []
    
    public init(meta: [String:String]? = [:], events: [FeatureEvent]? = []) {
        self.meta = meta
        self.events = events
    }
}
