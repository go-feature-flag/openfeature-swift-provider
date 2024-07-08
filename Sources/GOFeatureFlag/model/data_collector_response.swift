import Foundation

struct DataCollectorResponse: Codable {
    var ingestedContentCount: Int

    public init(ingestedContentCount: Int = 0) {
        self.ingestedContentCount = ingestedContentCount
    }
}
