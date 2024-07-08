import Foundation

enum GoFeatureFlagError: Error, Equatable {
    static func == (lhs: GoFeatureFlagError, rhs: GoFeatureFlagError) -> Bool {
        return type(of: lhs) == type(of: rhs)
    }

    case httpResponseCastError
    case noEventToSend
    case unmarshallError(error: Error)
    case apiUnauthorizedError(response: HTTPURLResponse)
    case forbiddenError(response: HTTPURLResponse)
    case unexpectedResponseError(response: HTTPURLResponse)
}
