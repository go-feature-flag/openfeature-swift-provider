import Foundation

public protocol NetworkingService {
    func doRequest(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkingService {
    public func doRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await data(for: request)
    }
}
