import Foundation

enum GoFeatureFlagError: Error, Equatable {
    static func == (left: GoFeatureFlagError, right: GoFeatureFlagError) -> Bool {
        return type(of: left) == type(of: right)
    }

    case httpResponseCastError
    case noEventToSend
    case unmarshallError(error: Error)
    case apiUnauthorizedError(response: HTTPURLResponse)
    case forbiddenError(response: HTTPURLResponse)
    case unexpectedResponseError(response: HTTPURLResponse)
}
