import Foundation

public enum InvalidOptions: Error, Equatable {
    case invalidEndpoint(message: String)

    public static func == (leftHandSide: InvalidOptions, rightHandSide: InvalidOptions) -> Bool {
        return type(of: leftHandSide) == type(of: rightHandSide)
    }
}
