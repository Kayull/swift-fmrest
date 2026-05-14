# swift-fmrest

swift-fmrest is a Swift package wrapper around the FileMaker Data API for Apple-platform Swift apps.

```swift
import swift_fmrest

let server = try FMServer(
    url: "https://example.com",
    username: "admin",
    password: "admin",
    database: "Devices",
    layout: "Devices"
)

try await server.login()
defer { Task { try? await server.logout() } }

let record = try await server.getRecord(id: 1)
print(record["name"]?.stringValue ?? "")
```

## Creating And Finding Records

```swift
let newID = try await server.createRecord(fieldData: [
    "name": "FMUser",
    "model": "MacBook Pro",
])

let foundset = try await server.find(query: [
    ["model": "MacBook Pro"],
    ["model": "MacBook Air"],
])
```

## Other Data API Calls

```swift
let cloudServer = try FMServer(
    url: "https://example.com",
    database: "Devices",
    layout: "Devices"
)

try await cloudServer.loginWithClarisID(token: clarisIDToken)
let isBusy = try await cloudServer.validateSession()

let duplicateID = try await server.duplicateRecord(id: 1)

try await server.createRecord(
    fieldData: ["status": "New"],
    options: FMWriteOptions(entryMode: .script),
    scripts: FMScripts(after: FMScriptCall("Post Create", parameter: "1"))
)

let layoutValueLists = try await server.getLayout(metadata: .valueLists, recordID: 1)
```

## Typed Model Decoding

```swift
struct Contact: Decodable {
    let name: String
    let model: String
}

let record = try await server.getRecord(id: 1)
let contact = try record.decoded(as: Contact.self)
```

## Supported Core Features

- Basic, OAuth identity provider, Claris ID, external FileMaker data source, and external OAuth data source login
- Explicit logout and session validation
- Create, read, update, duplicate, delete, find, and list records
- Script execution and script result tracking
- Metadata routes for product info, databases, layouts, scripts, fields, portals, and value lists
- Global field updates
- Container upload and file fetch helpers, including upload modification ID checks
- Portal, sort, range, response layout, date format, write option, and script hook request parameters
- Injectable HTTP transport for unit tests
- Typed errors for FileMaker API errors, transport failures, invalid JSON, malformed responses, bad gateway responses, and local record misuse

```swift
import swift_fmrest
```

## Attribution

This Swift package is based on the API shape and behavior of `python-fmrest` by David Hamann, which is licensed under the MIT License.
