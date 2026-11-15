//
//  http_trace_toolApp.swift
//  http-trace-tool
//

import SwiftUI

@main
struct HTTPTraceApp: App {
  @StateObject private var store = TrafficStore.shared
  @StateObject private var vpn = BackgroundVPNController()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(store)
        .environmentObject(vpn)
    }
  }
}
