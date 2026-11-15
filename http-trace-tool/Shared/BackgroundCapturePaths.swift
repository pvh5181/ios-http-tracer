//
//  BackgroundCapturePaths.swift
//  http-trace-tool
//

import Foundation

/// The VPN extension and the containing app share capture files through an
/// App Group. Each capture is written as a one-entry HAR file and drained by the
/// app the next time it is active.
enum BackgroundCapturePaths {
  static let appGroupIdentifier = "group.itsover.http-trace-tool"
  private static let directoryName = "BackgroundCaptures"
  private static let recordingKey = "backgroundCaptureRecording"
  private static let maxQueuedFiles = 5_000
  private static let lock = NSLock()
  private static var writesSinceTrim = 0

  static var isRecording: Bool {
    UserDefaults(suiteName: appGroupIdentifier)?.object(forKey: recordingKey) as? Bool ?? true
  }

  static func setRecording(_ isRecording: Bool) {
    UserDefaults(suiteName: appGroupIdentifier)?.set(isRecording, forKey: recordingKey)
  }

  static var directoryURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  @discardableResult
  static func ensureDirectory() throws -> URL {
    guard let directoryURL else {
      throw BackgroundCaptureError.appGroupUnavailable
    }
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    return directoryURL
  }

  static func write(_ transaction: HTTPTransaction) {
    guard isRecording else { return }

    lock.lock()
    defer { lock.unlock() }

    do {
      let directory = try ensureDirectory()
      let data = try HARCodec.encode([transaction])
      let file = directory.appendingPathComponent("\(UUID().uuidString).har")
      try data.write(to: file, options: .atomic)

      writesSinceTrim += 1
      if writesSinceTrim >= 100 {
        writesSinceTrim = 0
        trimOldestCaptures(in: directory)
      }
    } catch {
      NSLog("HTTP Trace background capture write failed: \(error.localizedDescription)")
    }
  }

  private static func trimOldestCaptures(in directory: URL) {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: Array(keys)
      ), files.count > maxQueuedFiles
    else { return }

    let sorted = files.sorted {
      let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
      let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
      return left < right
    }

    for file in sorted.prefix(files.count - maxQueuedFiles) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  static func drain(source: CaptureSource = .backgroundVPN) -> [HTTPTransaction] {
    lock.lock()
    defer { lock.unlock() }

    guard let directory = directoryURL,
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
    else { return [] }

    var transactions: [HTTPTransaction] = []
    for file in files where file.pathExtension.lowercased() == "har" {
      guard let data = try? Data(contentsOf: file),
        let decoded = try? HARCodec.decode(data, source: source)
      else {
        try? FileManager.default.removeItem(at: file)
        continue
      }
      transactions.append(contentsOf: decoded)
      try? FileManager.default.removeItem(at: file)
    }

    return transactions.sorted { $0.startedAt > $1.startedAt }
  }
}

enum BackgroundCaptureError: LocalizedError {
  case appGroupUnavailable

  var errorDescription: String? {
    "The shared App Group is unavailable. Enable the App Groups capability for both targets."
  }
}
