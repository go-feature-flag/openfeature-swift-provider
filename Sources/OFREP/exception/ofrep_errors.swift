import Foundation

enum OfrepError: Error {
    case httpResponseCastError
    case unmarshallError(error: Error)
    case apiUnauthorizedError(response: HTTPURLResponse)
    case forbiddenError(response: HTTPURLResponse)
    case apiTooManyRequestsError(response: HTTPURLResponse)
    case unexpectedResponseError(response: HTTPURLResponse)
    case waitingRetryLater(date: Date?)
}
