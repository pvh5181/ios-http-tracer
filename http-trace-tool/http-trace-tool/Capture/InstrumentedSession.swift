//
//  InstrumentedSession.swift
//  http-trace-tool
//

import Foundation

enum InstrumentedSession {
  /// A URLSession that records every request and response through
  /// TrafficURLProtocol. Use this for any networking that should appear in the
  /// trace list.
  static let shared: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [TrafficURLProtocol.self]
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 60
    return URLSession(configuration: configuration)
  }()

  static func data(for request: URLRequest, source: CaptureSource) async throws -> (
    Data, URLResponse
  ) {
    var tagged = request
    tagged.markCaptureSource(source)
    return try await shared.data(for: tagged)
  }
}
