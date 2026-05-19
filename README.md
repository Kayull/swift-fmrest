# swift-fmrest

swift-fmrest is a Swift package wrapper around the FileMaker Data API for Apple-platform Swift apps.

## Installation

Add the package dependency using a released version tag:

```swift
.package(url: "https://github.com/Kayull/swift-fmrest", from: "0.1.0")
```

Then add the `swift-fmrest` product to your target.

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

## Transient Network Retries

`URLSessionFMHTTPTransport` preserves the underlying `URLError`, so callers can distinguish a temporary network failure from a FileMaker API error.

For flows that can safely retry the same request, wrap the base transport in `RetryingFMHTTPTransport`:

```swift
let baseTransport = URLSessionFMHTTPTransport()
let retryingTransport = RetryingFMHTTPTransport(
    baseTransport,
    retryPolicy: .transientNetwork
)

let server = try FMServer(
    url: "https://example.com",
    username: "admin",
    password: "admin",
    database: "Devices",
    layout: "Devices",
    transport: retryingTransport
)
```

The `.transientNetwork` policy retries common temporary `URLError` failures such as `.notConnectedToInternet`, `.networkConnectionLost`, `.timedOut`, DNS lookup failures, and host connection failures. The default policy uses three attempts with exponential backoff.

Retries are opt-in because retrying every request globally can duplicate non-idempotent writes if the server accepted the first request but the client lost the response. Use `RetryingFMHTTPTransport` where the calling workflow can tolerate a replay, or provide a narrower `FMRetryPolicy`.

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
