//
//  TrafficURLProtocol.swift
//  http-trace-tool
//

import Foundation

/// URLProtocol-based recorder. Add this class to a URLSession configuration to
/// capture that session's HTTP(S) traffic. It intentionally does not register
/// itself globally: Apple's URL loading system still owns TLS validation and
/// certificate pinning.
final class TrafficURLProtocol: URLProtocol {
  static let sourcePropertyKey = "com.httpTrace.captureSource"
  private static let internalPropertyKey = "com.httpTrace.internalRequest"

  private var dataTask: URLSessionDataTask?
  private var session: URLSession?
  private var startedAt = Date()
  private var source: CaptureSource = .urlSession
  private let stateLock = NSLock()
  private var stopped = false

  override class func canInit(with request: URLRequest) -> Bool {
    guard let scheme = request.url?.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return false }

    // Never capture the request we make inside the protocol, otherwise a
    // session that inherits this protocol class would recurse forever.
    return URLProtocol.property(forKey: internalPropertyKey, in: request) == nil
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard request.url != nil else {
      fail(with: URLError(.badURL))
      return
    }

    startedAt = Date()
    if let rawSource = URLProtocol.property(forKey: Self.sourcePropertyKey, in: request) as? String,
      let parsedSource = CaptureSource(rawValue: rawSource)
    {
      source = parsedSource
    }

    let requestSnapshot = Self.snapshot(of: request)

    var forwarded = request
    let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest
    if let mutable {
      URLProtocol.setProperty(true, forKey: Self.internalPropertyKey, in: mutable)
      forwarded = mutable as URLRequest
    }

    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = []
    let session = URLSession(configuration: configuration)
    self.session = session

    let task = session.dataTask(with: forwarded) { [weak self] data, response, error in
      guard let self else { return }
      guard !self.isStopped else { return }

      if let error {
        self.record(
          request: requestSnapshot,
          response: nil,
          data: nil,
          error: error
        )
        self.client?.urlProtocol(self, didFailWithError: error)
        self.cleanup()
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        let error = URLError(.badServerResponse)
        self.record(
          request: requestSnapshot,
          response: nil,
          data: nil,
          error: error
        )
        self.client?.urlProtocol(self, didFailWithError: error)
        self.cleanup()
        return
      }

      self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
      if let data, !data.isEmpty {
        self.client?.urlProtocol(self, didLoad: data)
      }
      self.client?.urlProtocolDidFinishLoading(self)

      self.record(
        request: requestSnapshot,
        response: httpResponse,
        data: data,
        error: nil
      )
      self.cleanup()
    }

    self.dataTask = task
    task.resume()
  }

  override func stopLoading() {
    stateLock.lock()
    stopped = true
    stateLock.unlock()
    dataTask?.cancel()
    session?.invalidateAndCancel()
  }

  private var isStopped: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return stopped
  }

  private func cleanup() {
    session?.finishTasksAndInvalidate()
    session = nil
    dataTask = nil
  }

  private func fail(with error: Error) {
    client?.urlProtocol(self, didFailWithError: error)
    let snapshot = Self.snapshot(of: request)
    let transaction = HTTPTransaction(
      startedAt: startedAt,
      duration: Date().timeIntervalSince(startedAt),
      request: snapshot,
      response: nil,
      errorMessage: error.localizedDescription,
      source: source
    )
    Task { @MainActor in
      TrafficStore.shared.record(transaction)
    }
  }

  private func record(
    request requestSnapshot: HTTPRequestSnapshot,
    response: HTTPURLResponse?,
    data: Data?,
    error: Error?
  ) {
    let finishedAt = Date()
    let mimeType = response?.mimeType
    let responseBody = data.map { CapturedBody(data: $0, mimeType: mimeType) }

    let responseSnapshot = response.map {
      HTTPResponseSnapshot(
        statusCode: $0.statusCode,
        headers: .from($0.allHeaderFields),
        body: responseBody,
        mimeType: $0.mimeType,
        expectedContentLength: $0.expectedContentLength > 0 ? $0.expectedContentLength : nil,
        receivedAt: finishedAt
      )
    }

    let transaction = HTTPTransaction(
      startedAt: startedAt,
      duration: finishedAt.timeIntervalSince(startedAt),
      request: requestSnapshot,
      response: responseSnapshot,
      errorMessage: error?.localizedDescription,
      source: source
    )

    Task { @MainActor in
      TrafficStore.shared.record(transaction)
    }
  }

  private static func snapshot(of request: URLRequest) -> HTTPRequestSnapshot {
    let headers = [HTTPHeader].from(request.allHTTPHeaderFields ?? [:])
    let contentType = request.value(forHTTPHeaderField: "Content-Type")
    let body = request.httpBody.map { CapturedBody(data: $0, mimeType: contentType) }
    return HTTPRequestSnapshot(
      method: request.httpMethod ?? "GET",
      url: request.url?.absoluteString ?? "",
      headers: headers,
      body: body,
      capturedAt: Date()
    )
  }
}

extension URLRequest {
  /// Tags a request so its capture is attributed to the right feature.
  mutating func markCaptureSource(_ source: CaptureSource) {
    let mutable = (self as NSURLRequest).mutableCopy() as? NSMutableURLRequest
    guard let mutable else { return }
    URLProtocol.setProperty(
      source.rawValue,
      forKey: TrafficURLProtocol.sourcePropertyKey,
      in: mutable
    )
    self = mutable as URLRequest
  }
}
