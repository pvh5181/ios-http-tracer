//
//  HTTPMessageParser.swift
//  HTTPTraceTunnel
//

import Foundation

struct ParsedProxyRequest {
  let method: String
  let target: String
  let version: String
  let headers: [HTTPHeader]
  let body: Data
  let consumedBytes: Int
}

struct ParsedProxyResponse {
  let statusCode: Int
  let headers: [HTTPHeader]
  let body: Data
  let expectedContentLength: Int64?
}

enum HTTPMessageParser {
  static let crlf = Data("\r\n".utf8)
  static let crlfcrlf = Data("\r\n\r\n".utf8)

  static func parseRequest(from buffer: Data) -> ParsedProxyRequest? {
    guard let headerRange = buffer.range(of: crlfcrlf) else { return nil }
    let headerData = buffer[buffer.startIndex..<headerRange.lowerBound]
    guard let headerText = String(data: headerData, encoding: .isoLatin1) else { return nil }

    var lines = headerText.components(separatedBy: "\r\n")
    guard let startLine = lines.first else { return nil }
    lines.removeFirst()

    let parts = startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard parts.count == 3 else { return nil }

    let headers = parseHeaders(lines)
    let bodyStart = headerRange.upperBound
    let availableBody = buffer.subdata(in: bodyStart..<buffer.endIndex)

    let contentLength = headers.value(for: "Content-Length").flatMap(Int.init) ?? 0
    let isChunked =
      headers.value(for: "Transfer-Encoding")?
      .localizedCaseInsensitiveContains("chunked") == true

    let body: Data
    let consumedBytes: Int
    if isChunked {
      guard let length = chunkedMessageLength(in: buffer, startingAt: bodyStart) else { return nil }
      body = buffer.subdata(in: bodyStart..<(bodyStart + length))
      consumedBytes = bodyStart + length
    } else {
      guard availableBody.count >= contentLength else { return nil }
      body = Data(availableBody.prefix(contentLength))
      consumedBytes = bodyStart + contentLength
    }

    return ParsedProxyRequest(
      method: String(parts[0]),
      target: String(parts[1]),
      version: String(parts[2]),
      headers: headers,
      body: body,
      consumedBytes: consumedBytes
    )
  }

  static func parseResponse(
    from buffer: Data,
    requestMethod: String,
    connectionClosed: Bool
  ) -> ParsedProxyResponse? {
    var searchStart = buffer.startIndex

    while true {
      guard let headerRange = buffer.range(of: crlfcrlf, in: searchStart..<buffer.endIndex) else {
        return nil
      }
      let headerData = buffer[searchStart..<headerRange.lowerBound]
      guard let headerText = String(data: headerData, encoding: .isoLatin1) else { return nil }

      var lines = headerText.components(separatedBy: "\r\n")
      guard let statusLine = lines.first else { return nil }
      lines.removeFirst()

      let statusParts = statusLine.split(
        separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      guard statusParts.count >= 2,
        let statusCode = Int(statusParts[1])
      else { return nil }

      let bodyStart = headerRange.upperBound
      if statusCode == 100 {
        searchStart = bodyStart
        continue
      }

      let headers = parseHeaders(lines)
      if statusCode == 101 {
        return ParsedProxyResponse(
          statusCode: 101,
          headers: headers,
          body: Data(),
          expectedContentLength: 0
        )
      }
      if (100...199).contains(statusCode) {
        searchStart = bodyStart
        continue
      }
      let bodyAvailable = buffer.subdata(in: bodyStart..<buffer.endIndex)
      let isChunked =
        headers.value(for: "Transfer-Encoding")?
        .localizedCaseInsensitiveContains("chunked") == true
      let contentLength = headers.value(for: "Content-Length").flatMap(Int.init)

      if requestMethod.caseInsensitiveCompare("HEAD") == .orderedSame
        || statusCode == 204
        || statusCode == 304
      {
        return ParsedProxyResponse(
          statusCode: statusCode,
          headers: headers,
          body: Data(),
          expectedContentLength: 0
        )
      }

      if isChunked {
        guard let length = chunkedMessageLength(in: buffer, startingAt: bodyStart) else {
          if connectionClosed {
            return ParsedProxyResponse(
              statusCode: statusCode,
              headers: headers,
              body: bodyAvailable,
              expectedContentLength: contentLength.map(Int64.init)
            )
          }
          return nil
        }
        return ParsedProxyResponse(
          statusCode: statusCode,
          headers: headers,
          body: buffer.subdata(in: bodyStart..<(bodyStart + length)),
          expectedContentLength: contentLength.map(Int64.init)
        )
      }

      if let contentLength {
        if bodyAvailable.count >= contentLength {
          return ParsedProxyResponse(
            statusCode: statusCode,
            headers: headers,
            body: Data(bodyAvailable.prefix(contentLength)),
            expectedContentLength: Int64(contentLength)
          )
        }
        if connectionClosed {
          return ParsedProxyResponse(
            statusCode: statusCode,
            headers: headers,
            body: bodyAvailable,
            expectedContentLength: Int64(contentLength)
          )
        }
        return nil
      }

      guard connectionClosed else { return nil }
      return ParsedProxyResponse(
        statusCode: statusCode,
        headers: headers,
        body: bodyAvailable,
        expectedContentLength: nil
      )
    }
  }

  static func splitHostPort(_ value: String, defaultPort: Int) -> (host: String, port: Int)? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasPrefix("[") {
      guard let close = trimmed.firstIndex(of: "]") else { return nil }
      let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
      let remainder = trimmed[trimmed.index(after: close)...]
      let port =
        remainder.hasPrefix(":")
        ? Int(remainder.dropFirst())
        : defaultPort
      guard let port, (1...65_535).contains(port) else { return nil }
      return (host, port)
    }

    if let colon = trimmed.lastIndex(of: ":"), trimmed[..<colon].contains(":") == false {
      let host = String(trimmed[..<colon])
      if let port = Int(trimmed[trimmed.index(after: colon)...]),
        (1...65_535).contains(port)
      {
        return (host, port)
      }
    }

    return (trimmed, defaultPort)
  }

  static func absoluteURL(for request: ParsedProxyRequest, hostHeader: String?) -> (
    url: URL, host: String, port: Int
  )? {
    if let url = URL(string: request.target),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = url.host
    {
      return (url, host, url.port ?? (scheme == "https" ? 443 : 80))
    }

    guard let hostHeader,
      let (host, port) = splitHostPort(hostHeader, defaultPort: 80)
    else { return nil }

    let path = request.target.hasPrefix("/") ? request.target : "/\(request.target)"
    let raw = "http://\(hostHeader)\(path)"
    guard let url = URL(string: raw) else { return nil }
    return (url, host, port)
  }

  static func originFormTarget(for request: ParsedProxyRequest) -> String {
    if let url = URL(string: request.target),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      let path = url.path.isEmpty ? "/" : url.path
      if let query = url.query {
        return "\(path)?\(query)"
      }
      return path
    }
    return request.target.hasPrefix("/") ? request.target : "/\(request.target)"
  }

  private static func parseHeaders(_ lines: [String]) -> [HTTPHeader] {
    lines.compactMap { line in
      guard let colon = line.firstIndex(of: ":") else { return nil }
      let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
      let value = String(line[line.index(after: colon)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      return HTTPHeader(name: name, value: value)
    }
  }

  private static func chunkedMessageLength(in data: Data, startingAt start: Data.Index) -> Int? {
    var index = start
    while true {
      guard let lineRange = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
      let lineData = data[index..<lineRange.lowerBound]
      guard let line = String(data: lineData, encoding: .isoLatin1),
        let sizeToken = line.split(separator: ";", maxSplits: 1).first,
        let size = Int(sizeToken.trimmingCharacters(in: .whitespaces), radix: 16)
      else { return nil }

      index = lineRange.upperBound
      if size == 0 {
        if data[index..<data.endIndex].starts(with: crlf) {
          return index + 2 - start
        }
        if let trailers = data.range(of: crlfcrlf, in: index..<data.endIndex) {
          return trailers.upperBound - start
        }
        return nil
      }

      let chunkEnd = index + size
      guard chunkEnd + 2 <= data.endIndex else { return nil }
      guard data[chunkEnd..<(chunkEnd + 2)] == crlf else { return nil }
      index = chunkEnd + 2
    }
  }
}
