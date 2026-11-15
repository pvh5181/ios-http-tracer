//
//  HTTPTransaction.swift
//  http-trace-tool
//

import Foundation

enum CaptureLimits {
  /// Bodies are capped so a single huge download cannot exhaust memory.
  static let maxBodyBytes = 2_000_000
  static let maxTransactions = 1_000
  static let maxHexPreviewBytes = 4_096
  static let maxPreviewBytes = 300_000
  static let backgroundBodyBytes = 512_000
}

enum CaptureSource: String, Codable, CaseIterable, Hashable {
  case requestLab = "Request Lab"
  case browser = "Browser"
  case urlSession = "URLSession"
  case backgroundVPN = "System VPN"
  case imported = "Imported"

  var iconName: String {
    switch self {
    case .requestLab: "paperplane.fill"
    case .browser: "safari.fill"
    case .urlSession: "network"
    case .backgroundVPN: "shield.lefthalf.filled"
    case .imported: "square.and.arrow.down.fill"
    }
  }
}

struct HTTPHeader: Codable, Hashable, Identifiable {
  var id = UUID()
  var name: String
  var value: String

  init(id: UUID = UUID(), name: String, value: String) {
    self.id = id
    self.name = name
    self.value = value
  }
}

struct CapturedBody: Codable, Hashable {
  var data: Data
  var totalByteCount: Int
  var isTruncated: Bool
  var mimeType: String?

  init(data: Data, mimeType: String? = nil, limit: Int = CaptureLimits.maxBodyBytes) {
    self.totalByteCount = data.count
    self.mimeType = mimeType
    if data.count > limit {
      self.data = Data(data.prefix(limit))
      self.isTruncated = true
    } else {
      self.data = data
      self.isTruncated = false
    }
  }

  var isEmpty: Bool { data.isEmpty }
  var byteCount: Int { totalByteCount }
}

struct HTTPRequestSnapshot: Codable, Hashable {
  var method: String
  var url: String
  var headers: [HTTPHeader]
  var body: CapturedBody?
  var capturedAt: Date
}

struct HTTPResponseSnapshot: Codable, Hashable {
  var statusCode: Int
  var headers: [HTTPHeader]
  var body: CapturedBody?
  var mimeType: String?
  var expectedContentLength: Int64?
  var receivedAt: Date
}

struct HTTPTransaction: Codable, Hashable, Identifiable {
  var id: UUID
  var startedAt: Date
  var duration: TimeInterval
  var request: HTTPRequestSnapshot
  var response: HTTPResponseSnapshot?
  var errorMessage: String?
  var source: CaptureSource

  init(
    id: UUID = UUID(),
    startedAt: Date,
    duration: TimeInterval,
    request: HTTPRequestSnapshot,
    response: HTTPResponseSnapshot? = nil,
    errorMessage: String? = nil,
    source: CaptureSource
  ) {
    self.id = id
    self.startedAt = startedAt
    self.duration = duration
    self.request = request
    self.response = response
    self.errorMessage = errorMessage
    self.source = source
  }

  var url: URL? { URL(string: request.url) }
  var host: String { url?.host ?? "unknown host" }
  var path: String {
    guard let url else { return request.url }
    let path = url.path.isEmpty ? "/" : url.path
    return url.query.map { "\(path)?\($0)" } ?? path
  }

  var method: String { request.method.uppercased() }
  var statusCode: Int? { response?.statusCode }
  var isError: Bool { errorMessage != nil || (statusCode ?? 0) >= 400 || statusCode == nil }
  var totalBytes: Int { (request.body?.byteCount ?? 0) + (response?.body?.byteCount ?? 0) }

  var statusText: String {
    if let code = statusCode, code > 0 {
      return HTTPStatusText.text(for: code)
    }
    return "No response"
  }

  var searchableText: String {
    var parts = [
      request.method,
      request.url,
      request.body.map { BodyDecoder.text(from: $0) } ?? "",
      response.map { "\($0.statusCode)" } ?? "",
      errorMessage ?? "",
    ]
    parts.append(contentsOf: request.headers.map { "\($0.name): \($0.value)" })
    parts.append(contentsOf: response?.headers.map { "\($0.name): \($0.value)" } ?? [])
    if let response {
      parts.append(BodyDecoder.text(from: response.body))
    }
    return parts.joined(separator: "\n").lowercased()
  }
}

extension Array where Element == HTTPHeader {
  var dictionary: [String: String] {
    reduce(into: [:]) { result, header in
      if let existing = result[header.name] {
        result[header.name] = existing + ", " + header.value
      } else {
        result[header.name] = header.value
      }
    }
  }

  func value(for name: String) -> String? {
    first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  static func from(_ dictionary: [AnyHashable: Any]) -> [HTTPHeader] {
    dictionary.compactMap { key, value in
      guard let name = key as? String else { return nil }
      return HTTPHeader(name: name, value: String(describing: value))
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func from(_ dictionary: [String: String]) -> [HTTPHeader] {
    dictionary.map { HTTPHeader(name: $0.key, value: $0.value) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}
