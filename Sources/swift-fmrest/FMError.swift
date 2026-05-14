import Foundation

public enum FMError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case requestFailed(String)
    case badJSON(String)
    case malformedResponse(String)
    case badGateway
    case fileMaker(code: Int?, message: String)
    case recordError(String)
}

extension FMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            "Invalid swift-fmrest configuration: \(message)"
        case let .requestFailed(message):
            "swift-fmrest request failed: \(message)"
        case let .badJSON(message):
            "FileMaker Server returned invalid JSON: \(message)"
        case let .malformedResponse(message):
            "FileMaker Server returned a malformed response: \(message)"
        case .badGateway:
            "Web server returned 502 Bad Gateway. Check that the FileMaker Data API is enabled and responding."
        case let .fileMaker(code, message):
            "FileMaker Server returned error \(code.map(String.init) ?? "unknown"): \(message)"
        case let .recordError(message):
            "FMRecord error: \(message)"
        }
    }
}

public enum FMSErrorCode: Int, Sendable {
    case success = 0
    case recordMissing = 101
    case invalidUserPassword = 212
    case invalidDataAPIToken = 952
}
