//
//  TrafficStore.swift
//  http-trace-tool
//

import Combine
import Foundation

struct TrafficStats {
  let requestCount: Int
  let errorCount: Int
  let byteCount: Int
  let averageDuration: TimeInterval

  static let empty = TrafficStats(requestCount: 0, errorCount: 0, byteCount: 0, averageDuration: 0)
}

@MainActor
final class TrafficStore: ObservableObject {
  static let shared = TrafficStore()

  @Published private(set) var transactions: [HTTPTransaction] = []
  @Published var isRecording: Bool {
    didSet { BackgroundCapturePaths.setRecording(isRecording) }
  }

  private init() {
    isRecording = BackgroundCapturePaths.isRecording
  }

  var stats: TrafficStats {
    guard !transactions.isEmpty else { return .empty }
    let errors = transactions.filter(\.isError).count
    let bytes = transactions.reduce(0) { $0 + $1.totalBytes }
    let totalDuration = transactions.reduce(0) { $0 + $1.duration }
    return TrafficStats(
      requestCount: transactions.count,
      errorCount: errors,
      byteCount: bytes,
      averageDuration: totalDuration / Double(transactions.count)
    )
  }

  func record(_ transaction: HTTPTransaction) {
    guard isRecording || transaction.source == .imported else { return }

    // While the VPN is active, the same app request can be seen by both
    // URLProtocol and the local proxy. Prefer the richer in-app capture.
    if transaction.source != .backgroundVPN {
      transactions.removeAll { existing in
        guard existing.source == .backgroundVPN else { return false }
        if isSameExchange(existing, transaction) { return true }
        return existing.method == "CONNECT"
          && existing.host == transaction.host
          && abs(existing.startedAt.timeIntervalSince(transaction.startedAt)) < 5
      }
    }

    transactions.insert(transaction, at: 0)
    trimToLimit()
  }

  /// Pulls HAR files written by the VPN extension into the live store.
  @discardableResult
  func refreshBackgroundCaptures() -> Int {
    let incoming = BackgroundCapturePaths.drain()
    guard !incoming.isEmpty else { return 0 }

    var merged = transactions
    var added = 0
    for transaction in incoming {
      guard !merged.contains(where: { $0.id == transaction.id }) else { continue }
      if merged.contains(where: { existing in
        existing.source != .backgroundVPN && isSameExchange(existing, transaction)
      }) {
        continue
      }
      if transaction.method == "CONNECT",
        merged.contains(where: { existing in
          existing.source != .backgroundVPN
            && existing.host == transaction.host
            && abs(existing.startedAt.timeIntervalSince(transaction.startedAt)) < 5
        })
      {
        continue
      }
      merged.append(transaction)
      added += 1
    }

    guard added > 0 else { return 0 }
    merged.sort { $0.startedAt > $1.startedAt }
    transactions = merged
    trimToLimit()
    return added
  }

  private func isSameExchange(_ lhs: HTTPTransaction, _ rhs: HTTPTransaction) -> Bool {
    lhs.method == rhs.method
      && lhs.request.url == rhs.request.url
      && abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) < 2.5
  }

  private func trimToLimit() {
    if transactions.count > CaptureLimits.maxTransactions {
      transactions.removeLast(transactions.count - CaptureLimits.maxTransactions)
    }
  }

  func remove(_ transaction: HTTPTransaction) {
    transactions.removeAll { $0.id == transaction.id }
  }

  func remove(at offsets: IndexSet, from visibleTransactions: [HTTPTransaction]) {
    let ids = Set(offsets.map { visibleTransactions[$0].id })
    transactions.removeAll { ids.contains($0.id) }
  }

  func clear() {
    transactions.removeAll()
  }

  @discardableResult
  func importHAR(data: Data) throws -> Int {
    let imported = try HARCodec.decode(data)
    guard !imported.isEmpty else { return 0 }
    transactions.insert(contentsOf: imported, at: 0)
    transactions.sort { $0.startedAt > $1.startedAt }
    trimToLimit()
    return imported.count
  }
}
