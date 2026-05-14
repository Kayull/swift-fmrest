import Foundation

public enum FMAPIVersion: String, Codable, Sendable {
    case v1
    case v2
    case vLatest
}

public enum FMDateFormat: String, Sendable {
    case us = "0"
    case file = "1"
    case iso8601 = "2"
}

public struct FMDataSource: Codable, Equatable, Sendable {
    public var database: String
    public var username: String
    public var password: String

    public init(database: String, username: String, password: String) {
        self.database = database
        self.username = username
        self.password = password
    }

    internal var value: FMValue {
        .object([
            "database": .string(database),
            "username": .string(username),
            "password": .string(password),
        ])
    }
}

public struct FMServerConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var username: String
    public var password: String
    public var database: String
    public var layout: String
    public var dataSources: [FMDataSource]
    public var apiVersion: FMAPIVersion
    public var timeout: TimeInterval
    public var autoRelogin: Bool

    public init(
        url: URL,
        username: String,
        password: String,
        database: String,
        layout: String,
        dataSources: [FMDataSource] = [],
        apiVersion: FMAPIVersion = .v1,
        timeout: TimeInterval = 10,
        autoRelogin: Bool = false
    ) throws {
        guard let scheme = url.scheme?.lowercased() else {
            throw FMError.invalidConfiguration("Server URL must include a scheme.")
        }

        let isHTTPS = scheme == "https"
        let isInternalHTTPService = scheme == "http" && url.port == 3000
        guard isHTTPS || isInternalHTTPService else {
            throw FMError.invalidConfiguration("Use HTTPS for FileMaker Data API calls, or http://host:3000 for the internal service.")
        }

        self.baseURL = url.normalizedFMBaseURL
        self.username = username
        self.password = password
        self.database = database
        self.layout = layout
        self.dataSources = dataSources
        self.apiVersion = apiVersion
        self.timeout = timeout
        self.autoRelogin = autoRelogin
    }

    public init(
        url: String,
        username: String,
        password: String,
        database: String,
        layout: String,
        dataSources: [FMDataSource] = [],
        apiVersion: FMAPIVersion = .v1,
        timeout: TimeInterval = 10,
        autoRelogin: Bool = false
    ) throws {
        guard let parsedURL = URL(string: url) else {
            throw FMError.invalidConfiguration("Server URL is not valid.")
        }

        try self.init(
            url: parsedURL,
            username: username,
            password: password,
            database: database,
            layout: layout,
            dataSources: dataSources,
            apiVersion: apiVersion,
            timeout: timeout,
            autoRelogin: autoRelogin
        )
    }
}

private extension URL {
    var normalizedFMBaseURL: URL {
        let absolute = absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: absolute) ?? self
    }
}

