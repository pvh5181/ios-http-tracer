//
//  Clipboard.swift
//  http-trace-tool
//

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

enum Clipboard {
  static func copy(_ value: String) {
    #if canImport(UIKit)
      UIPasteboard.general.string = value
    #elseif canImport(AppKit)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
    #endif
  }
}
