import Foundation

public enum InvalidOptions: Error, Equatable {
    case invalidEndpoint(message: String)

    public static func == (lhs: InvalidOptions, rhs: InvalidOptions) -> Bool {
        return type(of: lhs) == type(of: rhs)
    }
}
