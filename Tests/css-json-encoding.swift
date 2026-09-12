import Foundation

let css = "body::before { content: \"BiliPad\\nready\"; }"
let data = try JSONEncoder().encode(css)
let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
let decoded = try JSONDecoder().decode(String.self, from: data)

precondition(encoded.first == "\"")
precondition(encoded.last == "\"")
precondition(decoded == css)

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else {
        throw EncodingTestError.unexpectedNil
    }
    return value
}

private enum EncodingTestError: Error {
    case unexpectedNil
}
