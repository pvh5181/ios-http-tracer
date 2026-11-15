//
//  AppTheme.swift
//  http-trace-tool
//

import SwiftUI

enum AppTheme {
  static let accent = Color(red: 0.22, green: 0.82, blue: 0.76)
  static let background = Color(red: 0.045, green: 0.06, blue: 0.075)
  static let card = Color(red: 0.085, green: 0.105, blue: 0.13)
  static let cardElevated = Color(red: 0.12, green: 0.145, blue: 0.175)
  static let hairline = Color.white.opacity(0.08)
  static let secondaryText = Color.white.opacity(0.58)

  static func methodColor(_ method: String) -> Color {
    switch method.uppercased() {
    case "GET": Color(red: 0.36, green: 0.68, blue: 1.0)
    case "POST": Color(red: 0.36, green: 0.86, blue: 0.55)
    case "PUT": Color(red: 1.0, green: 0.72, blue: 0.32)
    case "PATCH": Color(red: 0.76, green: 0.58, blue: 1.0)
    case "DELETE": Color(red: 1.0, green: 0.42, blue: 0.46)
    default: Color(red: 0.65, green: 0.68, blue: 0.74)
    }
  }

  static func statusColor(_ code: Int?) -> Color {
    guard let code, code > 0 else { return Color(red: 1.0, green: 0.42, blue: 0.46) }
    switch code {
    case 100..<200: return Color(red: 0.65, green: 0.68, blue: 0.74)
    case 200..<300: return Color(red: 0.36, green: 0.86, blue: 0.55)
    case 300..<400: return Color(red: 0.36, green: 0.68, blue: 1.0)
    case 400..<500: return Color(red: 1.0, green: 0.72, blue: 0.32)
    default: return Color(red: 1.0, green: 0.42, blue: 0.46)
    }
  }
}
