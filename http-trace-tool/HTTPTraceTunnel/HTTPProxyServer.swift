//
//  HTTPProxyServer.swift
//  HTTPTraceTunnel
//

import Foundation
import Network

final class HTTPProxyServer {
  private let listenerQueue = DispatchQueue(
    label: "com.httpTrace.vpn.listener", qos: .userInitiated)
  private let stateLock = NSLock()
  private var connections: [UUID: HTTPProxyConnection] = [:]
  private var listener: NWListener?
  private var completionCalled = false
  private let onTransaction: (HTTPTransaction) -> Void

  init(onTransaction: @escaping (HTTPTransaction) -> Void = BackgroundCapturePaths.write) {
    self.onTransaction = onTransaction
  }

  func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
    listenerQueue.async { [weak self] in
      guard let self else { return }

      do {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
          host: .ipv4(.loopback),
          port: .any
        )

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
          self?.accept(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
          guard let self else { return }
          switch state {
          case .ready:
            guard let port = listener.port?.rawValue else {
              self.finishStart(
                .failure(ProxyError.upstream("Proxy listener did not get a port.")),
                completion
              )
              return
            }
            self.finishStart(.success(port), completion)
          case .failed(let error):
            self.finishStart(.failure(error), completion)
            self.stop()
          default:
            break
          }
        }

        listener.start(queue: self.listenerQueue)
      } catch {
        self.finishStart(.failure(error), completion)
      }
    }
  }

  func stop() {
    listenerQueue.async { [weak self] in
      guard let self else { return }
      self.listener?.cancel()
      self.listener = nil

      self.stateLock.lock()
      let active = Array(self.connections.values)
      self.connections.removeAll()
      self.stateLock.unlock()

      active.forEach { $0.cancel() }
    }
  }

  private func accept(_ connection: NWConnection) {
    let id = UUID()
    let queue = DispatchQueue(label: "com.httpTrace.vpn.connection.\(id.uuidString)")
    let proxyConnection = HTTPProxyConnection(
      client: connection,
      queue: queue,
      onTransaction: onTransaction
    ) { [weak self] in
      self?.remove(id)
    }

    stateLock.lock()
    connections[id] = proxyConnection
    stateLock.unlock()

    proxyConnection.start()
  }

  private func remove(_ id: UUID) {
    stateLock.lock()
    connections.removeValue(forKey: id)
    stateLock.unlock()
  }

  private func finishStart(
    _ result: Result<UInt16, Error>,
    _ completion: @escaping (Result<UInt16, Error>) -> Void
  ) {
    guard !completionCalled else { return }
    completionCalled = true
    completion(result)
  }
}
