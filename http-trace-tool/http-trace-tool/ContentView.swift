//
//  ContentView.swift
//  http-trace-tool
//

import SwiftUI

enum AppTab: Hashable {
  case traffic
  case browser
  case lab
  case guide
}

struct ContentView: View {
  @EnvironmentObject private var store: TrafficStore
  @EnvironmentObject private var vpn: BackgroundVPNController
  @Environment(\.scenePhase) private var scenePhase
  @State private var selection: AppTab = .traffic

  var body: some View {
    TabView(selection: $selection) {
      TrafficListView(
        openBrowser: { selection = .browser },
        openRequestLab: { selection = .lab }
      )
      .tabItem { Label("Trace", systemImage: "waveform.path.ecg") }
      .tag(AppTab.traffic)

      BrowserView(showTrace: { selection = .traffic })
        .tabItem { Label("Browser", systemImage: "safari") }
        .tag(AppTab.browser)

      RequestLabView(showTrace: { selection = .traffic })
        .tabItem { Label("Compose", systemImage: "square.and.pencil") }
        .tag(AppTab.lab)

      SystemCaptureView(openBrowser: { selection = .browser })
        .tabItem { Label("Guide", systemImage: "lock.shield") }
        .tag(AppTab.guide)
    }
    .tint(AppTheme.accent)
    .preferredColorScheme(.dark)
    .onAppear {
      store.refreshBackgroundCaptures()
      Task { await vpn.refresh() }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        store.refreshBackgroundCaptures()
        Task { await vpn.refresh() }
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if scenePhase == .active {
          store.refreshBackgroundCaptures()
        }
      }
    }
  }
}
