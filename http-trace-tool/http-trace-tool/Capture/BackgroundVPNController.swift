//
//  BackgroundVPNController.swift
//  http-trace-tool
//

import Combine
import Foundation
@preconcurrency import NetworkExtension

@MainActor
final class BackgroundVPNController: ObservableObject {
  static var providerBundleIdentifier: String {
    (Bundle.main.bundleIdentifier ?? "itsover.http-trace-tool") + ".tunnel"
  }

  @Published private(set) var status: NEVPNStatus = .invalid
  @Published private(set) var isBusy = false
  @Published private(set) var errorMessage: String?

  private var manager: NETunnelProviderManager?
  private var statusObserver: NSObjectProtocol?

  init() {
    Task { await refresh() }
  }

  deinit {
    if let statusObserver {
      NotificationCenter.default.removeObserver(statusObserver)
    }
  }

  var isActive: Bool {
    status == .connected || status == .connecting || status == .reasserting
      || status == .disconnecting
  }

  var canStart: Bool {
    status == .disconnected || status == .invalid
  }

  var statusText: String {
    switch status {
    case .connected: "Active in background"
    case .connecting: "Connecting…"
    case .reasserting: "Reconnecting…"
    case .disconnecting: "Stopping…"
    case .disconnected: "Off"
    case .invalid: "Unavailable"
    @unknown default: "Unknown"
    }
  }

  func refresh() async {
    do {
      let managers = try await Self.loadManagers()
      let manager = managers.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == Self.providerBundleIdentifier
      }
      self.manager = manager
      errorMessage = nil
      if let manager {
        observe(manager.connection)
        status = manager.connection.status
      } else {
        status = .disconnected
      }
    } catch {
      status = .disconnected
      errorMessage = error.localizedDescription
    }
  }

  func start() async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }

    do {
      let manager: NETunnelProviderManager
      if let existing = try await Self.loadManagers().first(where: {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == Self.providerBundleIdentifier
      }) {
        manager = existing
      } else {
        manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.providerBundleIdentifier
        proto.serverAddress = "127.0.0.1"
        proto.providerConfiguration = [:]
        proto.disconnectOnSleep = false
        manager.protocolConfiguration = proto
        manager.localizedDescription = "HTTP Trace Background Capture"
      }

      if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
        proto.disconnectOnSleep = false
      }
      manager.isEnabled = true
      manager.isOnDemandEnabled = false
      try await Self.save(manager)
      try await Self.load(manager)

      self.manager = manager
      observe(manager.connection)
      try manager.connection.startVPNTunnel()
      status = manager.connection.status
    } catch {
      errorMessage = error.localizedDescription
      status = manager?.connection.status ?? .disconnected
    }
  }

  func stop() {
    errorMessage = nil
    manager?.connection.stopVPNTunnel()
    status = manager?.connection.status ?? .disconnected
  }

  private func observe(_ connection: NEVPNConnection) {
    if let statusObserver {
      NotificationCenter.default.removeObserver(statusObserver)
    }
    status = connection.status
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: connection,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.status = connection.status
        if connection.status == .connected {
          self?.errorMessage = nil
        }
      }
    }
  }

  private static func loadManagers() async throws -> [NETunnelProviderManager] {
    try await withCheckedThrowingContinuation { continuation in
      NETunnelProviderManager.loadAllFromPreferences { managers, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: managers ?? [])
        }
      }
    }
  }

  private static func save(_ manager: NETunnelProviderManager) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      manager.saveToPreferences { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private static func load(_ manager: NETunnelProviderManager) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      manager.loadFromPreferences { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}
