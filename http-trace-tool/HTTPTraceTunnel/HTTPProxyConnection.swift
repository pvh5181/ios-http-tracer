//
//  HTTPProxyConnection.swift
//  HTTPTraceTunnel
//

import Foundation
import Network

enum ProxyError: LocalizedError {
  case invalidRequest
  case invalidTarget
  case responseIncomplete
  case upstream(String)

  var errorDescription: String? {
    switch self {
    case .invalidRequest: "Malformed HTTP request."
    case .invalidTarget: "Could not determine the destination host."
    case .responseIncomplete:
      "The upstream connection closed before a complete response was received."
    case .upstream(let message): message
    }
  }
}

final class HTTPProxyConnection {
  private enum Mode {
    case request
    case connecting
    case response
    case tunnel
    case closed
  }

  private let client: NWConnection
  private let queue: DispatchQueue
  private let onTransaction: (HTTPTransaction) -> Void
  private let onClose: () -> Void

  private var mode: Mode = .request
  private var closed = false
  private var didSendResponseToClient = false
  private var didSendContinue = false
  private var clientSendsInFlight = 0
  private var shouldCloseAfterClientSends = false
  private var didRecordTransaction = false

  private let startedAt = Date()
  private var requestBuffer = Data()
  private var responseBuffer = Data()
  private var pendingClientData = Data()
  private var origin: NWConnection?

  private var currentRequest: ParsedProxyRequest?
  private var currentRequestSnapshot: HTTPRequestSnapshot?
  private var currentURL: URL?

  init(
    client: NWConnection,
    queue: DispatchQueue,
    onTransaction: @escaping (HTTPTransaction) -> Void,
    onClose: @escaping () -> Void
  ) {
    self.client = client
    self.queue = queue
    self.onTransaction = onTransaction
    self.onClose = onClose
  }

  func cancel() {
    queue.async { [weak self] in
      self?.close()
    }
  }

  func start() {
    client.stateUpdateHandler = { [weak self] state in
      guard let self, !self.closed else { return }
      switch state {
      case .ready:
        self.receiveClient()
      case .failed(let error):
        self.failRequest(error)
      case .cancelled:
        self.close()
      default:
        break
      }
    }
    client.start(queue: queue)
  }

  private func receiveClient() {
    guard !closed, mode == .request else { return }

    client.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1_024) {
      [weak self] data, _, isComplete, error in
      guard let self, !self.closed else { return }

      if let data, !data.isEmpty {
        self.requestBuffer.append(data)
        if self.processRequestBuffer() {
          return
        }
      }

      if let error {
        self.failRequest(error)
        return
      }

      if isComplete {
        self.close()
      } else if self.mode == .request {
        self.receiveClient()
      }
    }
  }

  /// Returns true when the buffer transitioned into a new mode and the receive
  /// loop should stop.
  private func processRequestBuffer() -> Bool {
    guard mode == .request else { return true }

    sendContinueIfNeeded()

    guard let request = HTTPMessageParser.parseRequest(from: requestBuffer) else {
      if requestBuffer.count > 16 * 1_024 * 1_024 {
        failRequest(ProxyError.invalidRequest)
        return true
      }
      return false
    }

    let leftoverStart = request.consumedBytes
    if leftoverStart < requestBuffer.count {
      pendingClientData = requestBuffer.subdata(in: leftoverStart..<requestBuffer.count)
    }
    requestBuffer.removeAll(keepingCapacity: false)
    mode = .connecting
    currentRequest = request

    if request.method.caseInsensitiveCompare("CONNECT") == .orderedSame {
      handleConnect(request)
    } else {
      handleHTTP(request)
    }
    return true
  }

  private func sendContinueIfNeeded() {
    guard !didSendContinue,
      let headerRange = requestBuffer.range(of: HTTPMessageParser.crlfcrlf),
      let headerText = String(
        data: requestBuffer[..<headerRange.lowerBound],
        encoding: .isoLatin1
      )?.lowercased()
    else { return }

    guard headerText.contains("expect:") && headerText.contains("100-continue") else { return }
    didSendContinue = true
    let response = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
    client.send(content: response, completion: .contentProcessed { _ in })
  }

  private func handleHTTP(_ request: ParsedProxyRequest) {
    let hostHeader = request.headers.value(for: "Host")
    guard let resolved = HTTPMessageParser.absoluteURL(for: request, hostHeader: hostHeader)
    else {
      failRequest(ProxyError.invalidTarget)
      return
    }

    currentURL = resolved.url
    currentRequestSnapshot = Self.requestSnapshot(
      from: request,
      url: resolved.url.absoluteString,
      startedAt: startedAt
    )

    let parameters = NWParameters.tcp
    guard let port = NWEndpoint.Port(rawValue: UInt16(resolved.port)) else {
      failRequest(ProxyError.invalidTarget)
      return
    }

    let origin = NWConnection(
      host: NWEndpoint.Host(resolved.host),
      port: port,
      using: parameters
    )
    self.origin = origin

    let effectiveHost =
      hostHeader ?? (resolved.port == 80 ? resolved.host : "\(resolved.host):\(resolved.port)")
    let forwarded = Self.forwardedRequest(
      request,
      originForm: HTTPMessageParser.originFormTarget(for: request),
      hostHeader: effectiveHost
    )

    origin.stateUpdateHandler = { [weak self] state in
      guard let self, !self.closed else { return }
      switch state {
      case .ready:
        self.mode = .response
        origin.send(
          content: forwarded,
          completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
              self.failRequest(ProxyError.upstream(error.localizedDescription))
            } else {
              self.receiveOrigin()
            }
          })
      case .failed(let error):
        self.failRequest(ProxyError.upstream(error.localizedDescription))
      case .cancelled:
        break
      default:
        break
      }
    }
    origin.start(queue: queue)
  }

  private func receiveOrigin() {
    guard !closed, mode == .response, let origin else { return }

    origin.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1_024) {
      [weak self] data, _, isComplete, error in
      guard let self, !self.closed else { return }

      if let data, !data.isEmpty {
        self.responseBuffer.append(data)
        self.forwardToClient(data)
      }

      if let error {
        self.failRequest(ProxyError.upstream(error.localizedDescription))
        return
      }

      self.processResponse(connectionClosed: isComplete)
    }
  }

  private func processResponse(connectionClosed: Bool) {
    guard let request = currentRequest else {
      failRequest(ProxyError.responseIncomplete)
      return
    }

    if let response = HTTPMessageParser.parseResponse(
      from: responseBuffer,
      requestMethod: request.method,
      connectionClosed: connectionClosed
    ) {
      recordSuccess(response)
      if response.statusCode == 101 {
        mode = .tunnel
        startTunnelRelay()
      } else {
        closeAfterClientSends()
      }
    } else if connectionClosed {
      failRequest(ProxyError.responseIncomplete)
    } else {
      receiveOrigin()
    }
  }

  private func forwardToClient(_ data: Data) {
    didSendResponseToClient = true
    clientSendsInFlight += 1
    client.send(
      content: data,
      completion: .contentProcessed { [weak self] error in
        guard let self else { return }
        self.clientSendsInFlight -= 1
        if error != nil {
          self.close()
        } else if self.shouldCloseAfterClientSends && self.clientSendsInFlight == 0 {
          self.close()
        }
      })
  }

  private func closeAfterClientSends() {
    shouldCloseAfterClientSends = true
    if clientSendsInFlight == 0 {
      close()
    }
  }

  private func handleConnect(_ request: ParsedProxyRequest) {
    guard let (host, port) = HTTPMessageParser.splitHostPort(request.target, defaultPort: 443),
      let endpointPort = NWEndpoint.Port(rawValue: UInt16(port))
    else {
      failRequest(ProxyError.invalidTarget)
      return
    }

    let hostForURL = host.contains(":") ? "[\(host)]" : host
    let urlString = "https://\(hostForURL):\(port)"
    currentURL = URL(string: urlString)
    currentRequestSnapshot = Self.requestSnapshot(
      from: request,
      url: urlString,
      startedAt: startedAt
    )

    let origin = NWConnection(
      host: NWEndpoint.Host(host),
      port: endpointPort,
      using: .tcp
    )
    self.origin = origin

    origin.stateUpdateHandler = { [weak self] state in
      guard let self, !self.closed else { return }
      switch state {
      case .ready:
        let established = Data(
          "HTTP/1.1 200 Connection Established\r\nProxy-Agent: HTTP Trace\r\n\r\n".utf8)
        self.didSendResponseToClient = true
        self.client.send(
          content: established,
          completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
              self.failRequest(ProxyError.upstream(error.localizedDescription))
              return
            }

            self.recordConnectSuccess(request)
            self.mode = .tunnel

            guard !self.pendingClientData.isEmpty else {
              self.startTunnelRelay()
              return
            }

            let pending = self.pendingClientData
            self.pendingClientData.removeAll(keepingCapacity: false)
            origin.send(
              content: pending,
              completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                  self.close()
                } else {
                  self.startTunnelRelay()
                }
              })
          })
      case .failed(let error):
        self.failRequest(ProxyError.upstream(error.localizedDescription))
      case .cancelled:
        break
      default:
        break
      }
    }
    origin.start(queue: queue)
  }

  private func startTunnelRelay() {
    guard !closed, mode == .tunnel else { return }
    relayClientToOrigin()
    relayOriginToClient()
  }

  private func relayClientToOrigin() {
    guard !closed, let origin else { return }

    client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
      [weak self] data, _, isComplete, error in
      guard let self, !self.closed else { return }

      if let data, !data.isEmpty {
        origin.send(
          content: data,
          completion: .contentProcessed { [weak self] sendError in
            guard let self, !self.closed else { return }
            if sendError != nil || isComplete {
              self.close()
            } else {
              self.relayClientToOrigin()
            }
          })
      } else if error != nil || isComplete {
        self.close()
      } else {
        self.relayClientToOrigin()
      }
    }
  }

  private func relayOriginToClient() {
    guard !closed, let origin else { return }

    origin.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
      [weak self] data, _, isComplete, error in
      guard let self, !self.closed else { return }

      if let data, !data.isEmpty {
        self.client.send(
          content: data,
          completion: .contentProcessed { [weak self] sendError in
            guard let self, !self.closed else { return }
            if sendError != nil || isComplete {
              self.close()
            } else {
              self.relayOriginToClient()
            }
          })
      } else if error != nil || isComplete {
        self.close()
      } else {
        self.relayOriginToClient()
      }
    }
  }

  private func recordSuccess(_ response: ParsedProxyResponse) {
    guard let requestSnapshot = currentRequestSnapshot else { return }
    let receivedAt = Date()
    let mimeType = response.headers.value(for: "Content-Type")?
      .split(separator: ";", maxSplits: 1)
      .first
      .map { String($0).trimmingCharacters(in: .whitespaces) }
    let body =
      response.body.isEmpty
      ? nil
      : CapturedBody(
        data: response.body,
        mimeType: mimeType,
        limit: CaptureLimits.backgroundBodyBytes
      )

    let responseSnapshot = HTTPResponseSnapshot(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
      mimeType: mimeType,
      expectedContentLength: response.expectedContentLength,
      receivedAt: receivedAt
    )

    let transaction = HTTPTransaction(
      startedAt: startedAt,
      duration: receivedAt.timeIntervalSince(startedAt),
      request: requestSnapshot,
      response: responseSnapshot,
      errorMessage: nil,
      source: .backgroundVPN
    )
    didRecordTransaction = true
    onTransaction(transaction)
  }

  private func recordConnectSuccess(_ request: ParsedProxyRequest) {
    guard let requestSnapshot = currentRequestSnapshot else { return }

    let responseHeaders = [
      HTTPHeader(name: "Proxy-Agent", value: "HTTP Trace"),
      HTTPHeader(
        name: "X-HTTP-Trace",
        value: "TLS tunnel — inner request and response headers are encrypted"
      ),
    ]
    let response = HTTPResponseSnapshot(
      statusCode: 200,
      headers: responseHeaders,
      body: nil,
      mimeType: nil,
      expectedContentLength: nil,
      receivedAt: Date()
    )
    let transaction = HTTPTransaction(
      startedAt: startedAt,
      duration: Date().timeIntervalSince(startedAt),
      request: requestSnapshot,
      response: response,
      errorMessage: nil,
      source: .backgroundVPN
    )
    didRecordTransaction = true
    onTransaction(transaction)
  }

  private func failRequest(_ error: Error) {
    guard !closed, !didRecordTransaction else {
      close()
      return
    }

    let message = error.localizedDescription
    let body = Data("HTTP Trace proxy: \(message)".utf8)
    let requestSnapshot =
      currentRequestSnapshot
      ?? HTTPRequestSnapshot(
        method: currentRequest?.method ?? "HTTP",
        url: currentURL?.absoluteString ?? "",
        headers: currentRequest?.headers ?? [],
        body: nil,
        capturedAt: startedAt
      )

    let responseHeaders = [
      HTTPHeader(name: "Content-Type", value: "text/plain; charset=utf-8"),
      HTTPHeader(name: "Content-Length", value: "\(body.count)"),
      HTTPHeader(name: "Connection", value: "close"),
    ]
    let response = HTTPResponseSnapshot(
      statusCode: 502,
      headers: responseHeaders,
      body: CapturedBody(data: body, mimeType: "text/plain"),
      mimeType: "text/plain",
      expectedContentLength: Int64(body.count),
      receivedAt: Date()
    )
    let transaction = HTTPTransaction(
      startedAt: startedAt,
      duration: Date().timeIntervalSince(startedAt),
      request: requestSnapshot,
      response: didSendResponseToClient ? nil : response,
      errorMessage: message,
      source: .backgroundVPN
    )
    didRecordTransaction = true
    onTransaction(transaction)

    guard !didSendResponseToClient else {
      close()
      return
    }

    didSendResponseToClient = true
    let head = [
      "HTTP/1.1 502 Bad Gateway",
      "Content-Type: text/plain; charset=utf-8",
      "Content-Length: \(body.count)",
      "Connection: close",
      "",
      "",
    ].joined(separator: "\r\n")

    client.send(
      content: Data(head.utf8) + body,
      completion: .contentProcessed { [weak self] _ in
        self?.close()
      })
  }

  private func close() {
    guard !closed else { return }
    closed = true
    mode = .closed
    client.cancel()
    origin?.cancel()
    origin = nil
    onClose()
  }

  private static func requestSnapshot(
    from request: ParsedProxyRequest,
    url: String,
    startedAt: Date
  ) -> HTTPRequestSnapshot {
    let contentType = request.headers.value(for: "Content-Type")
    let body =
      request.body.isEmpty
      ? nil
      : CapturedBody(
        data: request.body,
        mimeType: contentType,
        limit: CaptureLimits.backgroundBodyBytes
      )
    return HTTPRequestSnapshot(
      method: request.method,
      url: url,
      headers: request.headers,
      body: body,
      capturedAt: startedAt
    )
  }

  private static func forwardedRequest(
    _ request: ParsedProxyRequest,
    originForm: String,
    hostHeader: String
  ) -> Data {
    let removed = Set([
      "connection",
      "proxy-connection",
      "proxy-authorization",
      "expect",
    ])
    var headers = request.headers.filter { !removed.contains($0.name.lowercased()) }
    if headers.value(for: "Host") == nil {
      headers.append(HTTPHeader(name: "Host", value: hostHeader))
    }
    headers.removeAll { $0.name.caseInsensitiveCompare("Connection") == .orderedSame }
    let isUpgrade = headers.value(for: "Upgrade") != nil
    headers.append(HTTPHeader(name: "Connection", value: isUpgrade ? "Upgrade" : "close"))

    let headerText =
      headers
      .map { "\($0.name): \($0.value)" }
      .joined(separator: "\r\n")

    let head = "\(request.method) \(originForm) \(request.version)\r\n\(headerText)\r\n\r\n"
    return Data(head.utf8) + request.body
  }
}
