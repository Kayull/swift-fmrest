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

- Explicit login and logout
- Create, read, update, delete, find, and list records
- Script execution and script result tracking
- Metadata routes for product info, databases, layouts, scripts, fields, portals, and value lists
- Global field updates
- Container upload and file fetch helpers
- Injectable HTTP transport for unit tests
- Typed errors for FileMaker API errors, transport failures, invalid JSON, malformed responses, bad gateway responses, and local record misuse

## SwiftPM Installation

```swift
dependencies: [
    .package(path: "/Users/kyle/Documents/Work Projects/fmrest-wrapper")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["swift-fmrest"]
    )
]
```

Import the module with an underscore because Swift identifiers cannot contain hyphens:

```swift
import swift_fmrest
```

## Attribution

This Swift package is based on the API shape and behavior of `python-fmrest` by David Hamann, which is licensed under the MIT License.
