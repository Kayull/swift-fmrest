import Foundation

public enum FMLayoutMetadata: Sendable {
    case fields
    case portals
    case valueLists
    case all
}

public final class FMServer: @unchecked Sendable {
    public let configuration: FMServerConfiguration

    public var layout: String {
        get { state.withLock { $0.layout } }
        set { state.withLock { $0.layout = newValue } }
    }

    public private(set) var lastError: Int? {
        get { state.withLock { $0.lastError } }
        set { state.withLock { $0.lastError = newValue } }
    }

    public private(set) var lastScriptResult: [String: FMScriptResult] {
        get { state.withLock { $0.lastScriptResult } }
        set { state.withLock { $0.lastScriptResult = newValue } }
    }

    private let transport: any FMHTTPTransport

    private var token: String? {
        get { state.withLock { $0.token } }
        set { state.withLock { $0.token = newValue } }
    }

    /// Everything a request changes, behind a lock, so one server can be used from several
    /// tasks at once. With overlapping requests, `lastError` and `lastScriptResult` are those
    /// of whichever finished last.
    private struct State {
        var layout: String
        var lastError: Int?
        var lastScriptResult: [String: FMScriptResult] = [:]
        var token: String?
    }

    private let state: Locked<State>

    public init(
        configuration: FMServerConfiguration,
        transport: any FMHTTPTransport = URLSessionFMHTTPTransport()
    ) {
        self.configuration = configuration
        self.state = Locked(State(layout: configuration.layout))
        self.transport = transport
    }

    public convenience init(
        url: String,
        username: String,
        password: String,
        database: String,
        layout: String,
        dataSources: [FMDataSource] = [],
        apiVersion: FMAPIVersion = .v1,
        timeout: TimeInterval = 10,
        autoRelogin: Bool = false,
        transport: any FMHTTPTransport = URLSessionFMHTTPTransport()
    ) throws {
        let configuration = try FMServerConfiguration(
            url: url,
            username: username,
            password: password,
            database: database,
            layout: layout,
            dataSources: dataSources,
            apiVersion: apiVersion,
            timeout: timeout,
            autoRelogin: autoRelogin
        )
        self.init(configuration: configuration, transport: transport)
    }

    public convenience init(
        url: String,
        database: String,
        layout: String,
        dataSources: [FMDataSource] = [],
        apiVersion: FMAPIVersion = .v1,
        timeout: TimeInterval = 10,
        autoRelogin: Bool = false,
        transport: any FMHTTPTransport = URLSessionFMHTTPTransport()
    ) throws {
        let configuration = try FMServerConfiguration(
            url: url,
            database: database,
            layout: layout,
            dataSources: dataSources,
            apiVersion: apiVersion,
            timeout: timeout,
            autoRelogin: autoRelogin
        )
        self.init(configuration: configuration, transport: transport)
    }

    @discardableResult
    public func login(dataSources: [FMDataSource]? = nil) async throws -> String? {
        let selectedDataSources = dataSources ?? configuration.dataSources
        let response = try await callFileMaker(
            method: "POST",
            path: authPath(token: ""),
            body: loginBody(dataSources: selectedDataSources),
            authMode: .basic
        )
        token = response["token"]?.stringValue
        return token
    }

    @discardableResult
    public func loginWithOAuth(
        requestID: String,
        identifier: String,
        dataSources: [FMDataSource]? = nil
    ) async throws -> String? {
        let selectedDataSources = dataSources ?? configuration.dataSources
        let response = try await callFileMaker(
            method: "POST",
            path: authPath(token: ""),
            body: loginBody(dataSources: selectedDataSources),
            authMode: .oauth(requestID: requestID, identifier: identifier)
        )
        token = response["token"]?.stringValue
        return token
    }

    @discardableResult
    public func loginWithClarisID(token clarisIDToken: String) async throws -> String? {
        let response = try await callFileMaker(
            method: "POST",
            path: authPath(token: ""),
            body: [:],
            authMode: .clarisID(clarisIDToken)
        )
        token = response["token"]?.stringValue
        return token
    }

    @discardableResult
    public func logout() async throws -> Bool {
        let logoutToken = token ?? ""
        token = nil

        _ = try await callFileMaker(
            method: "DELETE",
            path: authPath(token: logoutToken),
            authMode: .none
        )
        return lastError == FMSErrorCode.success.rawValue
    }

    public func validateSession() async throws -> Bool {
        try await performWithAutoRelogin {
            let response = try await self.callFileMaker(
                method: "GET",
                path: self.validateSessionPath()
            )
            guard let isSessionInUse = response["isSessionInUse"]?.boolValue else {
                throw FMError.malformedResponse("Validate session response did not contain isSessionInUse.")
            }
            return isSessionInUse
        }
    }

    @discardableResult
    public func create(_ record: FMRecord, requestLayout: String? = nil) async throws -> Int? {
        try await createRecord(
            fieldData: record.toDictionary(ignorePortals: true, ignoreInternalIDs: true),
            requestLayout: requestLayout
        )
    }

    @discardableResult
    public func createRecord(
        fieldData: [String: FMValue],
        portals: [String: FMValue]? = nil,
        options: FMWriteOptions? = nil,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil,
        dateFormat: FMDateFormat? = nil
    ) async throws -> Int? {
        try await performWithAutoRelogin {
            var requestData: [String: FMValue] = [
                "fieldData": .object(fieldData),
            ]

            if let portals {
                requestData["portalData"] = .object(portals)
            }

            if let options {
                requestData["options"] = options.value
            }

            if let dateFormat {
                requestData["dateformats"] = dateFormat.value
            }

            if let scripts {
                requestData.merge(scripts.valueParameters) { _, new in new }
            }

            let response = try await self.callFileMaker(
                method: "POST",
                path: self.recordsPath(layout: requestLayout),
                body: requestData
            )
            return response["recordId"]?.intValue
        }
    }

    @discardableResult
    public func edit(_ record: FMRecord, validateModificationID: Bool = false, requestLayout: String? = nil) async throws -> Bool {
        guard let recordID = record.recordID else {
            throw FMError.recordError("Cannot edit a record without a recordId.")
        }

        return try await editRecord(
            id: recordID,
            fieldData: record.modifications,
            modificationID: validateModificationID ? record.modificationID : nil,
            requestLayout: requestLayout
        )
    }

    @discardableResult
    public func editRecord(
        id recordID: Int,
        fieldData: [String: FMValue],
        modificationID: Int? = nil,
        portals: [String: FMValue]? = nil,
        options: FMWriteOptions? = nil,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil,
        dateFormat: FMDateFormat? = nil
    ) async throws -> Bool {
        try await performWithAutoRelogin {
            var requestData: [String: FMValue] = [
                "fieldData": .object(fieldData),
            ]

            if let modificationID {
                requestData["modId"] = .string(String(modificationID))
            }

            if let portals {
                requestData["portalData"] = .object(portals)
            }

            if let options {
                requestData["options"] = options.value
            }

            if let dateFormat {
                requestData["dateformats"] = dateFormat.value
            }

            if let scripts {
                requestData.merge(scripts.valueParameters) { _, new in new }
            }

            _ = try await self.callFileMaker(
                method: "PATCH",
                path: self.recordPath(recordID: recordID, layout: requestLayout),
                body: requestData
            )
            return self.lastError == FMSErrorCode.success.rawValue
        }
    }

    @discardableResult
    public func duplicateRecord(
        id recordID: Int,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil
    ) async throws -> Int? {
        try await performWithAutoRelogin {
            let response = try await self.callFileMaker(
                method: "POST",
                path: self.recordPath(recordID: recordID, layout: requestLayout),
                body: scripts?.valueParameters ?? [:]
            )
            return response["recordId"]?.intValue
        }
    }

    @discardableResult
    public func delete(_ record: FMRecord, requestLayout: String? = nil) async throws -> Bool {
        guard let recordID = record.recordID else {
            throw FMError.recordError("Cannot delete a record without a recordId.")
        }

        return try await deleteRecord(id: recordID, requestLayout: requestLayout)
    }

    @discardableResult
    public func deleteRecord(
        id recordID: Int,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil
    ) async throws -> Bool {
        try await performWithAutoRelogin {
            _ = try await self.callFileMaker(
                method: "DELETE",
                path: self.recordPath(recordID: recordID, layout: requestLayout),
                query: scripts?.queryParameters ?? [:]
            )
            return self.lastError == FMSErrorCode.success.rawValue
        }
    }

    public func getRecord(
        id recordID: Int,
        portals: [FMPortalRequest]? = nil,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil,
        responseLayout: String? = nil,
        dateFormat: FMDateFormat? = nil
    ) async throws -> FMRecord {
        try await performWithAutoRelogin {
            var query = self.portalQueryParameters(portals, namesAsString: true)
            query["dateformats"] = dateFormat?.rawValue
            query["layout.response"] = responseLayout

            if let scripts {
                query.merge(scripts.queryParameters) { _, new in new }
            }

            let response = try await self.callFileMaker(
                method: "GET",
                path: self.recordPath(recordID: recordID, layout: requestLayout),
                query: query
            )
            let foundset = try self.processFoundsetResponse(response)
            guard let record = foundset.records.first else {
                throw FMError.malformedResponse("Record response did not contain a record.")
            }
            return record
        }
    }

    public func getRecords(
        offset: Int = 1,
        limit: Int = 100,
        sort: [FMSort]? = nil,
        portals: [FMPortalRequest]? = nil,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil,
        responseLayout: String? = nil,
        dateFormat: FMDateFormat? = nil
    ) async throws -> FMFoundset {
        try await performWithAutoRelogin {
            var query = self.portalQueryParameters(portals, namesAsString: true)
            query["_offset"] = String(offset)
            query["_limit"] = String(limit)
            query["dateformats"] = dateFormat?.rawValue
            query["layout.response"] = responseLayout

            if let sort {
                query["_sort"] = try self.jsonString(sort)
            }

            if let scripts {
                query.merge(scripts.queryParameters) { _, new in new }
            }

            let response = try await self.callFileMaker(
                method: "GET",
                path: self.recordsPath(layout: requestLayout),
                query: query
            )
            return try self.processFoundsetResponse(response)
        }
    }

    public func find(
        query findQueries: [[String: FMValue]],
        sort: [FMSort]? = nil,
        offset: Int = 1,
        limit: Int = 100,
        portals: [FMPortalRequest]? = nil,
        scripts: FMScripts? = nil,
        requestLayout: String? = nil,
        responseLayout: String? = nil,
        dateFormat: FMDateFormat? = nil
    ) async throws -> FMFoundset {
        try await performWithAutoRelogin {
            var body: [String: FMValue] = [
                "query": .array(findQueries.map { .object($0) }),
                "limit": .string(String(limit)),
                "offset": .string(String(offset)),
            ]

            if let sort {
                body["sort"] = .array(sort.map(\.value))
            }

            if let responseLayout {
                body["layout.response"] = .string(responseLayout)
            }

            if let dateFormat {
                body["dateformats"] = dateFormat.value
            }

            if let scripts {
                body.merge(scripts.valueParameters) { _, new in new }
            }

            if let portals {
                body.merge(self.portalBodyParameters(portals)) { _, new in new }
            }

            let response = try await self.callFileMaker(
                method: "POST",
                path: self.findPath(layout: requestLayout),
                body: body
            )
            return try self.processFoundsetResponse(response)
        }
    }

    public func performScript(
        name: String,
        param: String? = nil,
        requestLayout: String? = nil
    ) async throws -> FMScriptResult {
        try await performWithAutoRelogin {
            let response = try await self.callFileMaker(
                method: "GET",
                path: self.scriptPath(name: name, layout: requestLayout),
                query: ["script.param": param]
            )
            return FMScriptResult(
                error: response["scriptError"]?.intValue,
                result: response["scriptResult"]?.stringValue
            )
        }
    }

    @discardableResult
    public func uploadContainer(
        recordID: Int,
        fieldName: String,
        fileURL: URL,
        repetition: Int = 1,
        modificationID: Int? = nil,
        requestLayout: String? = nil
    ) async throws -> Bool {
        try await performWithAutoRelogin {
            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileURL)
            } catch {
                throw FMError.requestFailed("Could not read upload file at \(fileURL.path): \(error.localizedDescription)")
            }

            let boundary = "Boundary-\(UUID().uuidString)"
            let body = self.multipartBody(
                boundary: boundary,
                fieldName: "upload",
                filename: fileURL.lastPathComponent,
                fileData: fileData
            )

            _ = try await self.callFileMaker(
                method: "POST",
                path: self.recordPath(recordID: recordID, layout: requestLayout)
                    + "/containers/\(self.encodePathSegment(fieldName))/\(repetition)",
                rawBody: body,
                query: ["modId": modificationID.map(String.init)],
                contentType: "multipart/form-data; boundary=\(boundary)"
            )
            return self.lastError == FMSErrorCode.success.rawValue
        }
    }

    public func fetchFile(from fileURL: URL) async throws -> FMFetchedFile {
        let request = FMHTTPRequest(
            method: "GET",
            url: fileURL,
            timeout: configuration.timeout
        )
        let response: FMHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as FMError {
            throw error
        } catch {
            throw FMError.requestFailed(error.localizedDescription)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw FMError.requestFailed("File request returned HTTP \(response.statusCode).")
        }

        return FMFetchedFile(
            filename: filename(from: fileURL),
            contentType: headerValue("Content-Type", in: response.headers),
            contentLength: headerValue("Content-Length", in: response.headers).flatMap(Int.init),
            data: response.body
        )
    }

    @discardableResult
    public func setGlobals(_ globals: [String: FMValue]) async throws -> Bool {
        try await performWithAutoRelogin {
            _ = try await self.callFileMaker(
                method: "PATCH",
                path: self.globalsPath(),
                body: ["globalFields": .object(globals)]
            )
            return self.lastError == FMSErrorCode.success.rawValue
        }
    }

    public func getProductInfo() async throws -> [String: FMValue] {
        let response = try await callFileMaker(
            method: "GET",
            path: metaProductPath(),
            authMode: .none,
            contentType: nil
        )
        guard let productInfo = response["productInfo"]?.objectValue else {
            throw FMError.malformedResponse("Product info response did not contain productInfo.")
        }
        return productInfo
    }

    public func getDatabases(auth: FMDatabaseListAuthentication = .configuredBasic) async throws -> [FMValue] {
        let response = try await callFileMaker(
            method: "GET",
            path: metaDatabasesPath(),
            authMode: authMode(for: auth),
            contentType: nil
        )
        return response["databases"]?.arrayValue ?? []
    }

    public func getLayouts() async throws -> [FMValue] {
        try await performWithAutoRelogin {
            let response = try await self.callFileMaker(method: "GET", path: self.metaLayoutsPath())
            return response["layouts"]?.arrayValue ?? []
        }
    }

    public func getScripts() async throws -> [FMValue] {
        try await performWithAutoRelogin {
            let response = try await self.callFileMaker(method: "GET", path: self.metaScriptsPath())
            return response["scripts"]?.arrayValue ?? []
        }
    }

    public func getLayout(
        _ targetLayout: String? = nil,
        metadata: FMLayoutMetadata = .fields,
        recordID: Int? = nil
    ) async throws -> FMValue {
        try await performWithAutoRelogin {
            let selectedLayout = targetLayout ?? self.layout
            let response = try await self.callFileMaker(
                method: "GET",
                path: self.metaLayoutsPath() + "/\(self.encodePathSegment(selectedLayout))",
                query: ["recordId": recordID.map(String.init)]
            )

            switch metadata {
            case .all:
                return .object(response)
            case .portals:
                return response["portalMetaData"] ?? .null
            case .valueLists:
                return response["valueLists"] ?? .null
            case .fields:
                return response["fieldMetaData"] ?? .null
            }
        }
    }

    public func getValueListValues(
        name: String,
        layout targetLayout: String? = nil
    ) async throws -> [(value: String, displayValue: String)] {
        let metadata = try await getLayout(targetLayout, metadata: .valueLists)
        guard let valueLists = metadata.arrayValue else { return [] }

        for valueList in valueLists {
            guard
                let object = valueList.objectValue,
                object["name"]?.stringValue == name,
                let values = object["values"]?.arrayValue
            else {
                continue
            }

            return values.compactMap { entry in
                guard let object = entry.objectValue, let value = object["value"]?.stringValue else {
                    return nil
                }
                return (value: value, displayValue: object["displayValue"]?.stringValue ?? "")
            }
        }

        return []
    }
}

private extension FMServer {
    enum AuthMode {
        case bearerIfPresent
        case basic
        case basicCredentials(username: String, password: String)
        case clarisID(String)
        case oauth(requestID: String, identifier: String)
        case none
    }

    struct FMEnvelope: Decodable {
        var response: FMValue?
        var messages: [FMMessage]
    }

    struct FMMessage: Decodable {
        var code: String
        var message: String?
    }

    func performWithAutoRelogin<T>(_ operation: () async throws -> T) async throws -> T {
        guard configuration.autoRelogin else {
            return try await operation()
        }

        do {
            return try await operation()
        } catch FMError.fileMaker(let code, _) where code == FMSErrorCode.invalidDataAPIToken.rawValue {
            token = nil
            _ = try await login()
            return try await operation()
        }
    }

    func callFileMaker(
        method: String,
        path: String,
        body: [String: FMValue]? = nil,
        rawBody: Data? = nil,
        query: [String: String?] = [:],
        authMode: AuthMode = .bearerIfPresent,
        contentType: String? = "application/json"
    ) async throws -> [String: FMValue] {
        let request = try makeRequest(
            method: method,
            path: path,
            body: body,
            rawBody: rawBody,
            query: query,
            authMode: authMode,
            contentType: contentType
        )

        let httpResponse: FMHTTPResponse
        do {
            httpResponse = try await transport.send(request)
        } catch let error as FMError {
            throw error
        } catch {
            throw FMError.requestFailed(error.localizedDescription)
        }

        if httpResponse.statusCode == 502 {
            throw FMError.badGateway
        }

        let envelope: FMEnvelope
        do {
            envelope = try JSONDecoder().decode(FMEnvelope.self, from: httpResponse.body)
        } catch {
            throw FMError.badJSON(error.localizedDescription)
        }

        guard let message = envelope.messages.first else {
            throw FMError.malformedResponse("Response did not contain FileMaker messages.")
        }

        let code = Int(message.code) ?? -1
        lastError = code

        let response: [String: FMValue]
        if let responseValue = envelope.response {
            guard let object = responseValue.objectValue else {
                throw FMError.malformedResponse("Response payload was not an object.")
            }
            response = object
        } else {
            response = [:]
        }

        var responseWithHeaders = response
        if
            responseWithHeaders["token"] == nil,
            let accessToken = headerValue("X-FM-Data-Access-Token", in: httpResponse.headers)
        {
            responseWithHeaders["token"] = .string(accessToken)
        }

        updateScriptResult(from: responseWithHeaders)

        guard code == FMSErrorCode.success.rawValue else {
            throw FMError.fileMaker(code: code, message: message.message ?? "Unknown error")
        }

        return responseWithHeaders
    }

    func makeRequest(
        method: String,
        path: String,
        body: [String: FMValue]?,
        rawBody: Data?,
        query: [String: String?],
        authMode: AuthMode,
        contentType: String?
    ) throws -> FMHTTPRequest {
        guard var components = URLComponents(string: configuration.baseURL.absoluteString + path) else {
            throw FMError.invalidConfiguration("Could not build request URL for path \(path).")
        }

        let queryItems = query
            .compactMap { key, value -> URLQueryItem? in
                guard let value else { return nil }
                return URLQueryItem(name: key, value: value)
            }
            .sorted { $0.name < $1.name }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw FMError.invalidConfiguration("Could not build request URL for path \(path).")
        }

        var headers: [String: String] = [:]
        if let contentType {
            headers["Content-Type"] = contentType
        }

        switch authMode {
        case .bearerIfPresent:
            if let token {
                headers["Authorization"] = "Bearer \(token)"
            }
        case .basic:
            headers["Authorization"] = basicAuthorization(username: configuration.username, password: configuration.password)
        case let .basicCredentials(username, password):
            headers["Authorization"] = basicAuthorization(username: username, password: password)
        case let .clarisID(token):
            headers["Authorization"] = "FMID \(token)"
        case let .oauth(requestID, identifier):
            headers["X-FM-Data-OAuth-Request-Id"] = requestID
            headers["X-FM-Data-OAuth-Identifier"] = identifier
        case .none:
            break
        }

        let requestBody: Data?
        if let rawBody {
            requestBody = rawBody
        } else if let body {
            requestBody = try JSONEncoder().encode(FMValue.object(body))
        } else {
            requestBody = nil
        }

        return FMHTTPRequest(
            method: method,
            url: url,
            headers: headers,
            body: requestBody,
            timeout: configuration.timeout
        )
    }

    func loginBody(dataSources: [FMDataSource]) -> [String: FMValue] {
        guard !dataSources.isEmpty else { return [:] }
        return ["fmDataSource": .array(dataSources.map(\.value))]
    }

    func authMode(for databaseListAuthentication: FMDatabaseListAuthentication) -> AuthMode {
        switch databaseListAuthentication {
        case .none:
            return .none
        case .configuredBasic:
            return .basic
        case let .basic(username, password):
            return .basicCredentials(username: username, password: password)
        }
    }

    func basicAuthorization(username: String, password: String) -> String {
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    func processFoundsetResponse(_ response: [String: FMValue]) throws -> FMFoundset {
        guard let data = response["data"]?.arrayValue else {
            throw FMError.malformedResponse("Foundset response did not contain data.")
        }

        let records = try data.map { value -> FMRecord in
            guard let record = value.objectValue else {
                throw FMError.malformedResponse("Foundset data entry was not an object.")
            }

            guard var fieldData = record["fieldData"]?.objectValue else {
                throw FMError.malformedResponse("Record response did not contain fieldData.")
            }

            fieldData["recordId"] = record["recordId"] ?? .null
            fieldData["modId"] = record["modId"] ?? .null

            let portalInfo = portalInfoByName(from: record["portalDataInfo"]?.arrayValue ?? [])
            var portals: [String: FMFoundset] = [:]

            for (portalName, rowsValue) in record["portalData"]?.objectValue ?? [:] {
                guard let rows = rowsValue.arrayValue else {
                    throw FMError.malformedResponse("Portal \(portalName) was not an array.")
                }

                let portalRecords = try rows.map { rowValue -> FMRecord in
                    guard let row = rowValue.objectValue else {
                        throw FMError.malformedResponse("Portal \(portalName) row was not an object.")
                    }
                    return FMRecord(fields: row, isPortalRecord: true)
                }

                portals[portalName] = FMFoundset(
                    records: portalRecords,
                    info: portalInfo[portalName] ?? [:]
                )
            }

            return FMRecord(fields: fieldData, portals: portals)
        }

        return FMFoundset(records: records, info: response["dataInfo"]?.objectValue ?? [:])
    }

    func portalInfoByName(from entries: [FMValue]) -> [String: [String: FMValue]] {
        var output: [String: [String: FMValue]] = [:]

        for entry in entries {
            guard let object = entry.objectValue else { continue }
            let identifier = object["portalObjectName"]?.stringValue ?? object["table"]?.stringValue
            if let identifier {
                output[identifier] = object
            }
        }

        return output
    }

    func updateScriptResult(from response: [String: FMValue]) {
        let phases: [(String, String, String)] = [
            ("prerequest", "scriptError.prerequest", "scriptResult.prerequest"),
            ("presort", "scriptError.presort", "scriptResult.presort"),
            ("after", "scriptError", "scriptResult"),
        ]

        lastScriptResult = phases.reduce(into: [:]) { result, phase in
            let error = response[phase.1]?.intValue
            guard error != nil else { return }
            result[phase.0] = FMScriptResult(
                error: error,
                result: response[phase.2]?.stringValue
            )
        }
    }

    func portalQueryParameters(_ portals: [FMPortalRequest]?, namesAsString: Bool) -> [String: String?] {
        guard let portals, !portals.isEmpty else { return [:] }

        let portalNames = portals.map(\.name)
        let portalValue: String
        if namesAsString {
            let data = (try? JSONEncoder().encode(portalNames)) ?? Data("[]".utf8)
            portalValue = String(data: data, encoding: .utf8) ?? "[]"
        } else {
            portalValue = portalNames.joined(separator: ",")
        }

        var output: [String: String?] = ["portal": portalValue]
        let prefix = namesAsString ? "_" : ""
        for portal in portals {
            output["\(prefix)offset.\(portal.name)"] = String(portal.offset)
            output["\(prefix)limit.\(portal.name)"] = String(portal.limit)
        }
        return output
    }

    func portalBodyParameters(_ portals: [FMPortalRequest]) -> [String: FMValue] {
        var output: [String: FMValue] = [
            "portal": .array(portals.map { .string($0.name) }),
        ]

        for portal in portals {
            output["offset.\(portal.name)"] = .int(portal.offset)
            output["limit.\(portal.name)"] = .int(portal.limit)
        }

        return output
    }

    func multipartBody(boundary: String, fieldName: String, filename: String, fileData: Data) -> Data {
        var data = Data()
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        data.appendUTF8("Content-Type: application/octet-stream\r\n\r\n")
        data.append(fileData)
        data.appendUTF8("\r\n--\(boundary)--\r\n")
        return data
    }

    func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw FMError.requestFailed("Could not encode JSON query parameter.")
        }
        return string
    }

    func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func filename(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.lastPathComponent
        }
        components.query = nil
        return components.url?.lastPathComponent ?? url.lastPathComponent
    }

    func apiPrefix() -> String {
        "/fmi/data/\(configuration.apiVersion.rawValue)"
    }

    func authPath(token: String) -> String {
        let sessionsPath = "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/sessions"
        guard !token.isEmpty else { return sessionsPath }
        return "\(sessionsPath)/\(encodePathSegment(token))"
    }

    func validateSessionPath() -> String {
        "\(apiPrefix())/validateSession"
    }

    func recordsPath(layout requestLayout: String?) -> String {
        "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/layouts/\(encodePathSegment(requestLayout ?? layout))/records"
    }

    func recordPath(recordID: Int, layout requestLayout: String?) -> String {
        "\(recordsPath(layout: requestLayout))/\(recordID)"
    }

    func findPath(layout requestLayout: String?) -> String {
        "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/layouts/\(encodePathSegment(requestLayout ?? layout))/_find"
    }

    func scriptPath(name: String, layout requestLayout: String?) -> String {
        "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/layouts/\(encodePathSegment(requestLayout ?? layout))/script/\(encodePathSegment(name))"
    }

    func globalsPath() -> String {
        "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/globals"
    }

    func metaProductPath() -> String {
        "\(apiPrefix())/productInfo"
    }

    func metaDatabasesPath() -> String {
        "\(apiPrefix())/databases"
    }

    func metaLayoutsPath() -> String {
        "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/layouts"
    }

    func metaScriptsPath() -> String {
        "\(apiPrefix())/databases/\(encodePathSegment(configuration.database))/scripts"
    }

    func encodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}

/// A value only read and changed while holding a lock.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
