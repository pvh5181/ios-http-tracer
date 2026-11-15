//
//  HAR.swift
//  http-trace-tool
//

import Foundation

// MARK: - HAR 1.2 wire format
//
// Most fields are optional while decoding so this importer also accepts HAR
// files produced by tools that omit optional keys.

struct HARFile: Codable {
  var log: HARLog
}

struct HARLog: Codable {
  var version: String?
  var creator: HARCreator?
  var entries: [HAREntry]
}

struct HARCreator: Codable {
  var name: String?
  var version: String?
}

struct HAREntry: Codable {
  var startedDateTime: String?
  var time: Double?
  var request: HARRequest?
  var response: HARResponse?
  var cache: HARCache?
  var timings: HARTimings?
}

struct HARRequest: Codable {
  var method: String?
  var url: String?
  var httpVersion: String?
  var headers: [HARNameValue]?
  var queryString: [HARNameValue]?
  var cookies: [HARNameValue]?
  var headersSize: Int?
  var bodySize: Int?
  var postData: HARPostData?
}

struct HARResponse: Codable {
  var status: Int?
  var statusText: String?
  var httpVersion: String?
  var headers: [HARNameValue]?
  var cookies: [HARNameValue]?
  var content: HARContent?
  var redirectURL: String?
  var headersSize: Int?
  var bodySize: Int?
}

struct HARContent: Codable {
  var size: Int?
  var compression: Int?
  var mimeType: String?
  var text: String?
  var encoding: String?
}

struct HARPostData: Codable {
  var mimeType: String?
  var params: [HARNameValue]?
  var text: String?
  var encoding: String?
}

struct HARNameValue: Codable {
  var name: String
  var value: String
}

struct HARCache: Codable {}

struct HARTimings: Codable {
  var blocked: Double?
  var dns: Double?
  var connect: Double?
  var send: Double?
  var wait: Double?
  var receive: Double?
  var ssl: Double?
}

// MARK: - Conversion

enum HARCodec {
  static func decode(_ data: Data, source: CaptureSource = .imported) throws -> [HTTPTransaction] {
    let file = try JSONDecoder().decode(HARFile.self, from: data)
    return file.log.entries.compactMap { makeTransaction(from: $0, source: source) }
  }

  static func encode(_ transactions: [HTTPTransaction]) throws -> Data {
    let entries = transactions.map(makeEntry)
    let file = HARFile(
      log: HARLog(
        version: "1.2",
        creator: HARCreator(name: "HTTP Trace", version: "1.0"),
        entries: entries
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(file)
  }

  static func exportURL(transactions: [HTTPTransaction]) throws -> URL {
    let data = try encode(transactions)
    let name = "HTTPTrace-\(Formatters.fileNameTimestamp()).har"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    return url
  }

  private static func makeTransaction(from entry: HAREntry, source: CaptureSource)
    -> HTTPTransaction?
  {
    guard let request = entry.request else { return nil }

    let startedAt = entry.startedDateTime.flatMap(Formatters.parseISO8601) ?? Date()
    let duration = max(entry.time ?? 0, 0) / 1_000
    let requestHeaders = (request.headers ?? []).map {
      HTTPHeader(name: $0.name, value: $0.value)
    }
    let contentType =
      requestHeaders.value(for: "Content-Type")
      ?? request.postData?.mimeType

    var requestBodyData: Data?
    if let postData = request.postData {
      if postData.encoding?.lowercased() == "base64", let text = postData.text {
        requestBodyData = Data(base64Encoded: text)
      } else if let text = postData.text {
        requestBodyData = text.data(using: .utf8)
      }
    }

    let requestSnapshot = HTTPRequestSnapshot(
      method: request.method ?? "GET",
      url: request.url ?? "",
      headers: requestHeaders,
      body: requestBodyData.map { CapturedBody(data: $0, mimeType: contentType) },
      capturedAt: startedAt
    )

    var responseSnapshot: HTTPResponseSnapshot?
    var errorMessage: String?

    if let response = entry.response {
      let status = response.status ?? 0
      let headers = (response.headers ?? []).map {
        HTTPHeader(name: $0.name, value: $0.value)
      }
      let mimeType = response.content?.mimeType ?? headers.value(for: "Content-Type")

      var responseBodyData: Data?
      if let content = response.content, let text = content.text {
        if content.encoding?.lowercased() == "base64" {
          responseBodyData = Data(base64Encoded: text)
        } else {
          responseBodyData = text.data(using: .utf8)
        }
      }

      responseSnapshot = HTTPResponseSnapshot(
        statusCode: status,
        headers: headers,
        body: responseBodyData.map { CapturedBody(data: $0, mimeType: mimeType) },
        mimeType: mimeType,
        expectedContentLength: response.content?.size.map(Int64.init),
        receivedAt: startedAt.addingTimeInterval(duration)
      )

      if status <= 0 {
        errorMessage = "The captured response did not contain a valid status code."
      }
    } else {
      errorMessage = "No response was recorded for this request."
    }

    return HTTPTransaction(
      startedAt: startedAt,
      duration: duration,
      request: requestSnapshot,
      response: responseSnapshot,
      errorMessage: errorMessage,
      source: source
    )
  }

  private static func makeEntry(from transaction: HTTPTransaction) -> HAREntry {
    let requestHeaders = transaction.request.headers
    let responseHeaders = transaction.response?.headers ?? []

    let postData: HARPostData? = transaction.request.body.flatMap { body in
      guard !body.data.isEmpty else { return nil }
      let encoded = encodeBodyText(body)
      return HARPostData(
        mimeType: body.mimeType ?? requestHeaders.value(for: "Content-Type"),
        params: nil,
        text: encoded.text,
        encoding: encoded.encoding
      )
    }

    let content: HARContent
    if let body = transaction.response?.body, !body.data.isEmpty {
      let encoded = encodeBodyText(body)
      content = HARContent(
        size: body.totalByteCount,
        compression: nil,
        mimeType: body.mimeType ?? transaction.response?.mimeType,
        text: encoded.text,
        encoding: encoded.encoding
      )
    } else {
      content = HARContent(
        size: 0,
        compression: nil,
        mimeType: transaction.response?.mimeType,
        text: nil,
        encoding: nil
      )
    }

    let harRequest = HARRequest(
      method: transaction.method,
      url: transaction.request.url,
      httpVersion: "HTTP/1.1",
      headers: requestHeaders.map { HARNameValue(name: $0.name, value: $0.value) },
      queryString: nil,
      cookies: nil,
      headersSize: headerSize(requestHeaders),
      bodySize: transaction.request.body?.totalByteCount ?? 0,
      postData: postData
    )

    let harResponse = HARResponse(
      status: transaction.statusCode ?? 0,
      statusText: transaction.response == nil ? "No response" : transaction.statusText,
      httpVersion: "HTTP/1.1",
      headers: responseHeaders.map { HARNameValue(name: $0.name, value: $0.value) },
      cookies: nil,
      content: content,
      redirectURL: responseHeaders.value(for: "Location") ?? "",
      headersSize: headerSize(responseHeaders),
      bodySize: transaction.response?.body?.totalByteCount ?? 0
    )

    let millis = max(transaction.duration, 0) * 1_000
    return HAREntry(
      startedDateTime: Formatters.iso8601(transaction.startedAt),
      time: millis,
      request: harRequest,
      response: harResponse,
      cache: HARCache(),
      timings: HARTimings(
        blocked: 0,
        dns: -1,
        connect: -1,
        send: 0,
        wait: millis,
        receive: 0,
        ssl: -1
      )
    )
  }

  private static func encodeBodyText(_ body: CapturedBody) -> (text: String, encoding: String?) {
    if let text = String(data: body.data, encoding: .utf8),
      BodyDecoder.isText(mimeType: body.mimeType, data: body.data)
    {
      return (text, nil)
    }
    return (body.data.base64EncodedString(), "base64")
  }

  private static func headerSize(_ headers: [HTTPHeader]) -> Int {
    headers.reduce(2) { size, header in
      size + header.name.utf8.count + header.value.utf8.count + 4
    }
  }
}
