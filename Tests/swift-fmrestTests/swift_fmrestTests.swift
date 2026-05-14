import Foundation
import Testing
@testable import swift_fmrest

actor MockTransport: FMHTTPTransport {
    private var responses: [FMHTTPResponse]
    private var requests: [FMHTTPRequest] = []

    init(responses: [FMHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: FMHTTPRequest) async throws -> FMHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw FMError.requestFailed("No mock response queued.")
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [FMHTTPRequest] {
        requests
    }
}

@Test func configurationRejectsPlainHTTPExceptInternalService() throws {
    #expect(throws: FMError.self) {
        _ = try FMServerConfiguration(
            url: "http://127.0.0.1",
            username: "demo",
            password: "demo",
            database: "Demo",
            layout: "Demo"
        )
    }

    let configuration = try FMServerConfiguration(
        url: "http://127.0.0.1:3000",
        username: "demo",
        password: "demo",
        database: "Demo",
        layout: "Demo"
    )
    #expect(configuration.baseURL.absoluteString == "http://127.0.0.1:3000")
}

@Test func loginAndLogoutUseExpectedAuthAndPaths() async throws {
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "abc123"])),
        try envelope(),
    ])
    let server = try makeServer(transport: transport)

    let token = try await server.login()
    #expect(token == "abc123")
    #expect(try await server.logout())

    let requests = await transport.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[0].method == "POST")
    #expect(requests[0].url.path == "/fmi/data/v1/databases/Demo/sessions")
    #expect(requests[0].headers["Authorization"] == "Basic ZGVtbzpkZW1v")
    #expect(try bodyObject(requests[0])["fmDataSource"] == .array([]))

    #expect(requests[1].method == "DELETE")
    #expect(requests[1].url.path == "/fmi/data/v1/databases/Demo/sessions/abc123")
    #expect(requests[1].headers["Authorization"] == nil)
}

@Test func createRecordBuildsPayloadAndUsesBearerToken() async throws {
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "session-token"])),
        try envelope(response: .object(["recordId": "42"])),
    ])
    let server = try makeServer(transport: transport)

    _ = try await server.login()
    let recordID = try await server.createRecord(
        fieldData: ["name": "David", "drink": "Coffee"],
        portals: [
            "notes": .array([
                .object(["Notes::note": "Hello"]),
            ]),
        ],
        scripts: FMScripts(after: FMScriptCall("afterScript", parameter: "param")),
        requestLayout: "People",
        dateFormat: .iso8601
    )

    #expect(recordID == 42)

    let request = await transport.recordedRequests()[1]
    #expect(request.method == "POST")
    #expect(request.url.path == "/fmi/data/v1/databases/Demo/layouts/People/records")
    #expect(request.headers["Authorization"] == "Bearer session-token")

    let body = try bodyObject(request)
    #expect(body["fieldData"]?.objectValue?["name"] == "David")
    #expect(body["portalData"]?.objectValue?["notes"]?.arrayValue?.count == 1)
    #expect(body["script"] == "afterScript")
    #expect(body["script.param"] == "param")
    #expect(body["dateformats"] == "2")
}

@Test func getRecordParsesFieldsPortalsInfoAndScriptResults() async throws {
    let response: FMValue = .object([
        "data": .array([
            .object([
                "recordId": "1",
                "modId": "7",
                "fieldData": .object([
                    "name": "David",
                    "drink": "Coffee",
                ]),
                "portalDataInfo": .array([
                    .object([
                        "portalObjectName": "notes",
                        "foundCount": 1,
                    ]),
                ]),
                "portalData": .object([
                    "notes": .array([
                        .object([
                            "recordId": "3",
                            "Notes::note": "Test note",
                        ]),
                    ]),
                ]),
            ]),
        ]),
        "scriptError": "0",
        "scriptResult": "Done",
    ])
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "session-token"])),
        try envelope(response: response),
    ])
    let server = try makeServer(transport: transport)

    _ = try await server.login()
    let record = try await server.getRecord(
        id: 1,
        portals: [FMPortalRequest(name: "notes", offset: 2, limit: 5)],
        scripts: FMScripts(after: FMScriptCall("script", parameter: "input")),
        responseLayout: "Limited"
    )

    #expect(record.recordID == 1)
    #expect(record.modificationID == 7)
    #expect(record.name == "David")
    #expect(record.portal(named: "notes")?[0]["Notes::note"] == "Test note")
    #expect(record.portal(named: "notes")?.info["foundCount"] == 1)
    #expect(server.lastScriptResult["after"] == FMScriptResult(error: 0, result: "Done"))

    let request = await transport.recordedRequests()[1]
    let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.contains(URLQueryItem(name: "portal", value: "[\"notes\"]")))
    #expect(query.contains(URLQueryItem(name: "_offset.notes", value: "2")))
    #expect(query.contains(URLQueryItem(name: "_limit.notes", value: "5")))
    #expect(query.contains(URLQueryItem(name: "layout.response", value: "Limited")))
    #expect(query.contains(URLQueryItem(name: "script", value: "script")))
    #expect(query.contains(URLQueryItem(name: "script.param", value: "input")))
}

@Test func findBuildsBodyWithSortPortalsScriptsAndResponseLayout() async throws {
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "session-token"])),
        try envelope(response: foundsetResponse()),
    ])
    let server = try makeServer(transport: transport)

    _ = try await server.login()
    let foundset = try await server.find(
        query: [["drink": "Coffee"], ["omit": "true", "drink": "Tea"]],
        sort: [FMSort(fieldName: "name", sortOrder: .descend)],
        offset: 3,
        limit: 10,
        portals: [FMPortalRequest(name: "notes")],
        scripts: FMScripts(prerequest: FMScriptCall("before")),
        responseLayout: "Limited",
        dateFormat: .file
    )

    #expect(foundset.count == 1)
    #expect(foundset.info["foundCount"] == 1)

    let request = await transport.recordedRequests()[1]
    #expect(request.method == "POST")
    #expect(request.url.path == "/fmi/data/v1/databases/Demo/layouts/Demo/_find")

    let body = try bodyObject(request)
    #expect(body["query"]?.arrayValue?.count == 2)
    #expect(body["sort"]?.arrayValue?.first?.objectValue?["sortOrder"] == "descend")
    #expect(body["offset"] == "3")
    #expect(body["limit"] == "10")
    #expect(body["portal"] == .array(["notes"]))
    #expect(body["offset.notes"] == 1)
    #expect(body["limit.notes"] == 50)
    #expect(body["script.prerequest"] == "before")
    #expect(body["layout.response"] == "Limited")
    #expect(body["dateformats"] == "1")
}

@Test func editDeleteGlobalsAndMetadataRoutesAreBuiltCorrectly() async throws {
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "session-token"])),
        try envelope(),
        try envelope(),
        try envelope(),
        try envelope(response: .object(["productInfo": .object(["name": "FileMaker Server"])])),
        try envelope(response: .object(["databases": .array(["Demo"])])),
        try envelope(response: .object(["layouts": .array([.object(["name": "Demo"])])])),
        try envelope(response: .object(["scripts": .array([.object(["name": "Script"])])])),
        try envelope(response: .object([
            "valueLists": .array([
                .object([
                    "name": "Choices",
                    "values": .array([
                        .object(["value": "a", "displayValue": "A"]),
                    ]),
                ]),
            ]),
        ])),
    ])
    let server = try makeServer(transport: transport)

    _ = try await server.login()
    #expect(try await server.editRecord(id: 2, fieldData: ["name": "Updated"], modificationID: 9))
    #expect(try await server.deleteRecord(id: 2, scripts: FMScripts(after: FMScriptCall("after"))))
    #expect(try await server.setGlobals(["Table::g": "value"]))
    #expect(try await server.getProductInfo()["name"] == "FileMaker Server")
    #expect(try await server.getDatabases() == ["Demo"])
    #expect(try await server.getLayouts().count == 1)
    #expect(try await server.getScripts().count == 1)
    let values = try await server.getValueListValues(name: "Choices")
    #expect(values.count == 1)
    #expect(values[0].value == "a")
    #expect(values[0].displayValue == "A")

    let requests = await transport.recordedRequests()
    #expect(requests[1].method == "PATCH")
    #expect(requests[1].url.path == "/fmi/data/v1/databases/Demo/layouts/Demo/records/2")
    #expect(try bodyObject(requests[1])["modId"] == "9")

    #expect(requests[2].method == "DELETE")
    #expect(requests[2].url.query?.contains("script=after") == true)

    #expect(requests[3].method == "PATCH")
    #expect(requests[3].url.path == "/fmi/data/v1/databases/Demo/globals")

    #expect(requests[4].url.path == "/fmi/data/v1/productInfo")

    #expect(requests[5].url.path == "/fmi/data/v1/databases")
    #expect(requests[5].headers["Authorization"] == "Basic ZGVtbzpkZW1v")

    #expect(requests[8].url.path == "/fmi/data/v1/databases/Demo/layouts/Demo")
}

@Test func performScriptReturnsDedicatedScriptResult() async throws {
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "session-token"])),
        try envelope(response: .object([
            "scriptError": "0",
            "scriptResult": "Output",
        ])),
    ])
    let server = try makeServer(transport: transport)

    _ = try await server.login()
    let result = try await server.performScript(name: "testScript", param: "input")
    #expect(result == FMScriptResult(error: 0, result: "Output"))

    let request = await transport.recordedRequests()[1]
    #expect(request.url.path == "/fmi/data/v1/databases/Demo/layouts/Demo/script/testScript")
    #expect(request.url.query?.contains("script.param=input") == true)
}

@Test func recordTracksModificationsRejectsPortalWritesAndDecodesCodableModels() throws {
    struct Contact: Decodable, Equatable {
        var name: String
        var drink: String
    }

    var record = FMRecord(fields: [
        "name": "David",
        "drink": "Coffee",
        "recordId": "1",
        "modId": "2",
        "portal_notes": "placeholder",
    ])

    try record.setValue("David", forField: "name")
    #expect(!record.isDirty)

    try record.setValue("Tea", forField: "drink")
    #expect(record.isDirty)
    #expect(record.modifications == ["drink": "Tea"])
    #expect(record.toDictionary(ignorePortals: true, ignoreInternalIDs: true) == [
        "name": "David",
        "drink": "Tea",
        "portal_notes": "placeholder",
    ])

    #expect(throws: FMError.self) {
        try record.setValue("x", forField: "missing")
    }

    #expect(throws: FMError.self) {
        try record.setValue("x", forField: "portal_notes")
    }

    let decoded = try record.decoded(as: Contact.self)
    #expect(decoded == Contact(name: "David", drink: "Tea"))
}

@Test func failuresAreTypedAndAutoReloginCanRetryInvalidToken() async throws {
    let badJSONTransport = MockTransport(responses: [
        FMHTTPResponse(statusCode: 200, body: Data("not-json".utf8)),
    ])
    let badJSONServer = try makeServer(transport: badJSONTransport)
    await #expect(throws: FMError.self) {
        try await badJSONServer.login()
    }

    let badGatewayTransport = MockTransport(responses: [
        FMHTTPResponse(statusCode: 502, body: Data()),
    ])
    let badGatewayServer = try makeServer(transport: badGatewayTransport)
    await #expect(throws: FMError.badGateway) {
        try await badGatewayServer.login()
    }

    let errorTransport = MockTransport(responses: [
        try envelope(response: .object([:]), code: "212", message: "Invalid user or password"),
    ])
    let errorServer = try makeServer(transport: errorTransport)
    await #expect(throws: FMError.fileMaker(code: 212, message: "Invalid user or password")) {
        try await errorServer.login()
    }
    #expect(errorServer.lastError == 212)

    let reloginTransport = MockTransport(responses: [
        try envelope(response: .object(["token": "old-token"])),
        try envelope(response: .object([:]), code: "952", message: "Invalid FileMaker Data API token"),
        try envelope(response: .object(["token": "new-token"])),
        try envelope(response: foundsetResponse()),
    ])
    let reloginServer = try makeServer(autoRelogin: true, transport: reloginTransport)

    _ = try await reloginServer.login()
    let record = try await reloginServer.getRecord(id: 1)
    #expect(record.recordID == 1)

    let requests = await reloginTransport.recordedRequests()
    #expect(requests.count == 4)
    #expect(requests[1].headers["Authorization"] == "Bearer old-token")
    #expect(requests[3].headers["Authorization"] == "Bearer new-token")
}

@Test func uploadContainerAndFetchFileUseExpectedRequests() async throws {
    let tempFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("fmrest-\(UUID().uuidString).txt")
    try Data("hello".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let fileURL = try #require(URL(string: "https://files.example.com/Streaming_SSL/MainDB/file.txt?RCType=EmbeddedRCFileProcessor"))
    let transport = MockTransport(responses: [
        try envelope(response: .object(["token": "session-token"])),
        try envelope(),
        FMHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/plain", "Content-Length": "5"],
            body: Data("hello".utf8)
        ),
    ])
    let server = try makeServer(transport: transport)

    _ = try await server.login()
    #expect(try await server.uploadContainer(recordID: 1, fieldName: "portrait", fileURL: tempFile))
    let fetched = try await server.fetchFile(from: fileURL)

    #expect(fetched.filename == "file.txt")
    #expect(fetched.contentType == "text/plain")
    #expect(fetched.contentLength == 5)
    #expect(fetched.data == Data("hello".utf8))

    let requests = await transport.recordedRequests()
    #expect(requests[1].method == "POST")
    #expect(requests[1].url.path == "/fmi/data/v1/databases/Demo/layouts/Demo/records/1/containers/portrait/1")
    #expect(requests[1].headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
    #expect(String(data: requests[1].body ?? Data(), encoding: .utf8)?.contains("hello") == true)

    #expect(requests[2].method == "GET")
    #expect(requests[2].url == fileURL)
}

private func makeServer(
    autoRelogin: Bool = false,
    transport: any FMHTTPTransport
) throws -> FMServer {
    try FMServer(
        url: "https://111.111.111.111",
        username: "demo",
        password: "demo",
        database: "Demo",
        layout: "Demo",
        autoRelogin: autoRelogin,
        transport: transport
    )
}

private func envelope(
    response: FMValue = .object([:]),
    code: String = "0",
    message: String = "OK"
) throws -> FMHTTPResponse {
    let root: FMValue = .object([
        "response": response,
        "messages": .array([
            .object([
                "code": .string(code),
                "message": .string(message),
            ]),
        ]),
    ])
    return FMHTTPResponse(statusCode: 200, body: try JSONEncoder().encode(root))
}

private func foundsetResponse() -> FMValue {
    .object([
        "dataInfo": .object([
            "foundCount": 1,
            "returnedCount": 1,
        ]),
        "data": .array([
            .object([
                "recordId": "1",
                "modId": "2",
                "fieldData": .object([
                    "name": "David",
                    "drink": "Coffee",
                ]),
                "portalData": .object([:]),
            ]),
        ]),
    ])
}

private func bodyObject(_ request: FMHTTPRequest) throws -> [String: FMValue] {
    let body = try #require(request.body)
    let value = try JSONDecoder().decode(FMValue.self, from: body)
    return try #require(value.objectValue)
}
