import Foundation

public struct FMHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 10
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct FMHTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol FMHTTPTransport: Sendable {
    func send(_ request: FMHTTPRequest) async throws -> FMHTTPResponse
}

public struct FMRetryPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var initialDelay: TimeInterval
    public var delayMultiplier: Double
    public var retryableURLErrorCodes: Set<Int>

    public init(
        maxAttempts: Int,
        initialDelay: TimeInterval,
        delayMultiplier: Double = 2,
        retryableURLErrorCodes: Set<URLError.Code> = FMRetryPolicy.defaultRetryableURLErrorCodes
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelay = max(0, initialDelay)
        self.delayMultiplier = max(1, delayMultiplier)
        self.retryableURLErrorCodes = Set(retryableURLErrorCodes.map(\.rawValue))
    }

    public static let none = FMRetryPolicy(maxAttempts: 1, initialDelay: 0, delayMultiplier: 1, retryableURLErrorCodes: [])

    public static let transientNetwork = FMRetryPolicy(maxAttempts: 3, initialDelay: 0.35)

    public static let defaultRetryableURLErrorCodes: Set<URLError.Code> = [
        .cannotConnectToHost,
        .cannotFindHost,
        .dataNotAllowed,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .networkConnectionLost,
        .notConnectedToInternet,
        .resourceUnavailable,
        .timedOut,
    ]

    func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        if error is CancellationError { return false }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return retryableURLErrorCodes.contains(nsError.code)
    }
}

public final class RetryingFMHTTPTransport: FMHTTPTransport, @unchecked Sendable {
    private let wrapped: any FMHTTPTransport
    private let retryPolicy: FMRetryPolicy

    public init(_ wrapped: any FMHTTPTransport, retryPolicy: FMRetryPolicy = .transientNetwork) {
        self.wrapped = wrapped
        self.retryPolicy = retryPolicy
    }

    public func send(_ request: FMHTTPRequest) async throws -> FMHTTPResponse {
        var attempt = 1
        var delay = retryPolicy.initialDelay

        while true {
            do {
                return try await wrapped.send(request)
            } catch {
                guard retryPolicy.shouldRetry(error, attempt: attempt) else {
                    throw error
                }

                attempt += 1
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                delay *= retryPolicy.delayMultiplier
            }
        }
    }
}

public final class URLSessionFMHTTPTransport: FMHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: FMHTTPRequest) async throws -> FMHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FMError.requestFailed("Response was not an HTTP response.")
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }

        return FMHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }
}
