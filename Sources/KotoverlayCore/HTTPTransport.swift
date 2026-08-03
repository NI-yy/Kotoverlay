import Foundation

public struct HTTPDataResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let finalURL: URL?

    public init(data: Data, statusCode: Int, finalURL: URL? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.finalURL = finalURL
    }
}

public struct HTTPStreamMetadata: Sendable {
    public let statusCode: Int
    public let finalURL: URL?

    public init(statusCode: Int, finalURL: URL? = nil) {
        self.statusCode = statusCode
        self.finalURL = finalURL
    }
}

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPDataResponse

    func streamLines(
        for request: URLRequest,
        receive: @escaping @Sendable (String) async throws -> Void
    ) async throws -> HTTPStreamMetadata
}

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let delegate: NoRedirectURLSessionDelegate
    private let session: URLSession

    public init() {
        let delegate = NoRedirectURLSessionDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func data(for request: URLRequest) async throws -> HTTPDataResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPTransportError.nonHTTPResponse
        }
        return HTTPDataResponse(
            data: data,
            statusCode: response.statusCode,
            finalURL: response.url
        )
    }

    public func streamLines(
        for request: URLRequest,
        receive: @escaping @Sendable (String) async throws -> Void
    ) async throws -> HTTPStreamMetadata {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPTransportError.nonHTTPResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            return HTTPStreamMetadata(statusCode: response.statusCode, finalURL: response.url)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            try await receive(line)
        }
        return HTTPStreamMetadata(statusCode: response.statusCode, finalURL: response.url)
    }
}

public enum HTTPTransportError: Error, LocalizedError, Sendable {
    case nonHTTPResponse

    public var errorDescription: String? {
        "The local server returned a non-HTTP response."
    }
}
