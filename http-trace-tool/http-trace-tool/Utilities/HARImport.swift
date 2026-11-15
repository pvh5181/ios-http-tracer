//
//  HARImport.swift
//  http-trace-tool
//

import Foundation
import UniformTypeIdentifiers

enum HARFileTypes {
  static var allowed: [UTType] {
    var types: [UTType] = [.json, .data]
    if let har = UTType(filenameExtension: "har") {
      types.append(har)
    }
    return types
  }
}

enum HARImportError: LocalizedError {
  case unreadable
  case empty

  var errorDescription: String? {
    switch self {
    case .unreadable:
      "The file could not be read. Make sure it is a valid HAR export."
    case .empty:
      "No HTTP entries were found in this HAR file."
    }
  }
}

enum HARImport {
  @MainActor
  static func perform(url: URL, store: TrafficStore) throws -> Int {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess { url.stopAccessingSecurityScopedResource() }
    }

    guard let data = try? Data(contentsOf: url) else {
      throw HARImportError.unreadable
    }

    let count = try store.importHAR(data: data)
    guard count > 0 else { throw HARImportError.empty }
    return count
  }
}
