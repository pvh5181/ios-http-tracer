//
//  Formatting.swift
//  http-trace-tool
//

import Foundation

enum HTTPStatusText {
  static func text(for code: Int) -> String {
    switch code {
    case 100: "Continue"
    case 101: "Switching Protocols"
    case 200: "OK"
    case 201: "Created"
    case 202: "Accepted"
    case 204: "No Content"
    case 206: "Partial Content"
    case 301: "Moved Permanently"
    case 302: "Found"
    case 303: "See Other"
    case 304: "Not Modified"
    case 307: "Temporary Redirect"
    case 308: "Permanent Redirect"
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 403: "Forbidden"
    case 404: "Not Found"
    case 405: "Method Not Allowed"
    case 408: "Request Timeout"
    case 409: "Conflict"
    case 410: "Gone"
    case 418: "I'm a Teapot"
    case 422: "Unprocessable Content"
    case 429: "Too Many Requests"
    case 500: "Internal Server Error"
    case 501: "Not Implemented"
    case 502: "Bad Gateway"
    case 503: "Service Unavailable"
    case 504: "Gateway Timeout"
    default: HTTPURLResponse.localizedString(forStatusCode: code).capitalized
    }
  }
}

enum Formatters {
  static func duration(_ interval: TimeInterval) -> String {
    if interval < 1 {
      return "\(Int((interval * 1_000).rounded())) ms"
    }
    return String(format: "%.2f s", interval)
  }

  static func bytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
  }

  static func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .standard)
  }

  static func dateTime(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .standard)
  }

  static func compactDateTime(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
  }

  static func relative(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func parseISO8601(_ string: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: string) { return date }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: string)
  }

  static func fileNameTimestamp(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }
}

enum BodyDecoder {
  static func text(from body: CapturedBody?) -> String {
    guard let body else { return "" }
    return text(from: body.data, mimeType: body.mimeType)
  }

  static func text(from data: Data, mimeType: String? = nil) -> String {
    guard !data.isEmpty else { return "" }

    if let encoding = charsetEncoding(in: mimeType),
      let decoded = String(data: data, encoding: encoding)
    {
      return decoded
    }

    if let decoded = String(data: data, encoding: .utf8) {
      return decoded
    }

    if let decoded = String(data: data, encoding: .isoLatin1) {
      return decoded
    }

    return "Binary data (\(Formatters.bytes(data.count)))"
  }

  static func prettyJSON(from data: Data) -> String? {
    guard !data.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: data),
      JSONSerialization.isValidJSONObject(object),
      let pretty = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
    else { return nil }
    return String(data: pretty, encoding: .utf8)
  }

  static func isJSON(mimeType: String?, data: Data) -> Bool {
    if let mimeType, mimeType.localizedCaseInsensitiveContains("json") {
      return true
    }
    guard let first = data.first else { return false }
    return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
  }

  static func isText(mimeType: String?, data: Data) -> Bool {
    if let mimeType {
      let lower = mimeType.lowercased()
      if lower.hasPrefix("text/")
        || lower.contains("json")
        || lower.contains("xml")
        || lower.contains("javascript")
        || lower.contains("x-www-form-urlencoded")
        || lower.contains("graphql")
      {
        return true
      }
      if lower.hasPrefix("image/")
        || lower.hasPrefix("audio/")
        || lower.hasPrefix("video/")
        || lower.contains("octet-stream")
        || lower.contains("zip")
        || lower.contains("pdf")
      {
        return false
      }
    }
    return String(data: data, encoding: .utf8) != nil
  }

  static func hexDump(_ data: Data, limit: Int = CaptureLimits.maxHexPreviewBytes) -> String {
    let bytes = [UInt8](data.prefix(limit))
    guard !bytes.isEmpty else { return "" }

    return stride(from: 0, to: bytes.count, by: 16).map { offset in
      let slice = bytes[offset..<min(offset + 16, bytes.count)]
      let address = String(format: "%08X", offset)
      let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
      let paddedHex = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
      let ascii = slice.map { byte -> Character in
        (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
      }
      return "\(address)  \(paddedHex)  \(String(ascii))"
    }
    .joined(separator: "\n")
  }

  static func contentTypeText(_ mimeType: String?) -> String {
    guard let mimeType, !mimeType.isEmpty else { return "Unknown" }
    return mimeType
  }

  private static func charsetEncoding(in mimeType: String?) -> String.Encoding? {
    guard let mimeType,
      let range = mimeType.range(of: "charset=", options: .caseInsensitive)
    else { return nil }

    var charset = String(mimeType[range.upperBound...])
    if let semicolon = charset.firstIndex(of: ";") {
      charset = String(charset[..<semicolon])
    }
    charset = charset.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))

    switch charset.lowercased() {
    case "utf-8", "utf8": return .utf8
    case "iso-8859-1", "latin1", "latin-1": return .isoLatin1
    case "us-ascii", "ascii": return .ascii
    case "utf-16", "utf16": return .utf16
    case "utf-16le": return .utf16LittleEndian
    case "utf-16be": return .utf16BigEndian
    default: return nil
    }
  }
}
