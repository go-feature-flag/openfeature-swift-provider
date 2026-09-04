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

extension OfrepError: CustomStringConvertible {
    /// A human-readable message, unlike the bridged `localizedDescription` which only yields
    /// "The operation couldn't be completed. (OFREP.OfrepError error N.)".
    var description: String {
        switch self {
        case .httpResponseCastError:
            return "the OFREP API response was not a valid HTTP response"
        case .unmarshallError(let error):
            return "the OFREP API response could not be decoded: \(error)"
        case .apiUnauthorizedError:
            return "the OFREP API rejected the request as unauthorized (HTTP 401)"
        case .forbiddenError:
            return "the OFREP API rejected the request as forbidden (HTTP 403)"
        case .apiTooManyRequestsError:
            return "the OFREP API returned too many requests (429)"
        case .unexpectedResponseError(let response):
            return "the OFREP API returned an unexpected HTTP status code \(response.statusCode)"
        case .waitingRetryLater:
            return "waiting for the Retry-After window before calling the OFREP API again"
        }
    }
}
