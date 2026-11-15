//
//  SystemCaptureView.swift
//  http-trace-tool
//

import Foundation
import SwiftUI

struct SystemCaptureView: View {
  @EnvironmentObject private var store: TrafficStore
  @EnvironmentObject private var vpn: BackgroundVPNController
  let openBrowser: () -> Void

  @State private var showingImporter = false
  @State private var alert: AlertPayload?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          hero
          backgroundVPNCard
          captureModes
          systemCaptureSteps
          limitations
          importCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 30)
      }
      .background(AppTheme.background)
      .navigationTitle("Guide")
      .fileImporter(
        isPresented: $showingImporter,
        allowedContentTypes: HARFileTypes.allowed,
        allowsMultipleSelection: false
      ) { result in
        importHAR(result)
      }
      .alert(item: $alert) { payload in
        Alert(title: Text(payload.title), message: Text(payload.message))
      }
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack {
        ZStack {
          RoundedRectangle(cornerRadius: 13)
            .fill(
              LinearGradient(
                colors: [AppTheme.accent, Color(red: 0.25, green: 0.5, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 48, height: 48)
          Image(systemName: "lock.shield.fill")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(AppTheme.background)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("Capture beyond this app")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
          Text("The honest iOS version")
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.secondaryText)
        }
        Spacer()
      }

      Text(
        "iOS sandboxing prevents this app from reading other apps' sockets directly. The optional **background VPN** keeps a local proxy alive and captures HTTP from other apps even after you leave HTTP Trace. HTTPS is tunneled — for decrypted HTTPS headers, route the device through a trusted MITM proxy and import its HAR."
      )
      .font(.system(size: 12))
      .foregroundStyle(.white.opacity(0.78))
      .fixedSize(horizontal: false, vertical: true)

      Button(action: openBrowser) {
        Label("Try the in-app browser", systemImage: "safari")
      }
      .buttonStyle(PrimaryButtonStyle())
    }
    .padding(16)
    .background(
      LinearGradient(
        colors: [Color(red: 0.11, green: 0.16, blue: 0.19), AppTheme.card],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 18)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .strokeBorder(AppTheme.accent.opacity(0.16), lineWidth: 0.5)
    }
  }

  private var captureModes: some View {
    SectionCard(title: "What can be captured", icon: "waveform.path.ecg") {
      VStack(spacing: 12) {
        captureRow(
          icon: "shield.lefthalf.filled",
          title: "Background VPN",
          detail:
            "HTTP request/response headers and bodies from other apps while this app is closed. HTTPS connections appear as CONNECT host metadata unless an external MITM proxy is used."
        )
        Divider().overlay(AppTheme.hairline)
        captureRow(
          icon: "square.and.pencil",
          title: "Request Lab",
          detail:
            "Full request/response headers, bodies, status, and timing for requests you compose."
        )
        Divider().overlay(AppTheme.hairline)
        captureRow(
          icon: "safari",
          title: "In-app browser",
          detail:
            "Main-page navigation headers, response headers, status, timing, and rendered body."
        )
        Divider().overlay(AppTheme.hairline)
        captureRow(
          icon: "network",
          title: "Instrumented URLSession",
          detail: "Any networking your code sends through InstrumentedSession."
        )
      }
    }
  }

  private var backgroundVPNCard: some View {
    SectionCard(title: "On-device background capture", icon: "shield.lefthalf.filled") {
      VStack(alignment: .leading, spacing: 11) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(vpn.statusText)
              .font(.system(size: 13, weight: .semibold))
            Text("Local VPN · proxy runs in the Network Extension")
              .font(.system(size: 10))
              .foregroundStyle(AppTheme.secondaryText)
          }
          Spacer()
          if vpn.isBusy {
            ProgressView().controlSize(.small)
          } else {
            Button {
              Task {
                if vpn.isActive {
                  vpn.stop()
                } else {
                  await vpn.start()
                }
              }
            } label: {
              Text(vpn.isActive ? "Stop" : "Start")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(vpn.isActive ? Color.white.opacity(0.8) : AppTheme.background)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                  vpn.isActive ? Color.white.opacity(0.1) : AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
          }
        }

        Text(
          "This target requires the Network Extensions and App Groups capabilities, a paid Apple Developer account, and a provisioning profile for both the app and extension. Without those, iOS will reject the VPN configuration."
        )
        .font(.system(size: 10))
        .foregroundStyle(AppTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

        if let error = vpn.errorMessage {
          Text(error)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var systemCaptureSteps: some View {
    SectionCard(title: "Decrypted whole-device HTTPS capture", icon: "desktopcomputer") {
      VStack(alignment: .leading, spacing: 16) {
        step(
          number: 1,
          title: "Run a proxy on a computer",
          detail:
            "Use Proxyman, Charles Proxy, or mitmproxy on the same Wi-Fi network as the iPhone."
        )

        step(
          number: 2,
          title: "Point the iPhone's Wi-Fi proxy at it",
          detail:
            "Settings → Wi-Fi → (i) next to your network → Configure Proxy → Manual. Enter the computer's IP and proxy port."
        )

        step(
          number: 3,
          title: "Trust the proxy's HTTPS certificate",
          detail:
            "Install the certificate profile, then enable it in Settings → General → About → Certificate Trust Settings. Without this step, HTTPS shows as CONNECT tunnels only."
        )

        step(
          number: 4,
          title: "Use apps, then export a HAR",
          detail:
            "Interact with the app you want to inspect, then choose File → Export → HTTP Archive (.har) in the proxy."
        )

        step(
          number: 5,
          title: "Import the HAR here",
          detail:
            "Every entry becomes searchable, with its request/response headers and body. Tap a row to inspect the exchange."
        )

        HStack(spacing: 8) {
          Text("mitmproxy --mode regular@8080")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))

          Button {
            Clipboard.copy("mitmproxy --mode regular@8080")
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 11))
              .foregroundStyle(AppTheme.secondaryText)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var limitations: some View {
    SectionCard(title: "Important limits", icon: "exclamationmark.triangle") {
      VStack(alignment: .leading, spacing: 10) {
        limitation(
          "Background VPN and HTTPS",
          "The built-in background VPN sees full plain-HTTP headers, but HTTPS is an opaque CONNECT tunnel. Decrypting it requires a trusted MITM proxy with an installed/trusted root CA."
        )
        limitation(
          "Certificate pinning",
          "Apps that pin certificates reject a MITM proxy's CA. Those exchanges cannot be decrypted, even though connection metadata may still appear."
        )
        limitation(
          "VPN signing",
          "The background tunnel only works in a build signed with Network Extensions and App Groups entitlements. A normal free provisioning profile cannot start it."
        )
        limitation(
          "HTTP vs HTTPS",
          "Plain HTTP headers are visible directly. TLS itself is never weakened by this app.")
        limitation(
          "HAR body size",
          "Very large bodies may be truncated by the capturing proxy. This app also caps previews at \(Formatters.bytes(CaptureLimits.maxBodyBytes)) per body."
        )
      }
    }
  }

  private var importCard: some View {
    SectionCard(title: "Already have a HAR?", icon: "square.and.arrow.down") {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          "Import a HAR 1.2 file from Proxyman, Charles, Chrome DevTools, mitmproxy, or a packet capture tool that exports HAR."
        )
        .font(.system(size: 11))
        .foregroundStyle(AppTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

        Button {
          showingImporter = true
        } label: {
          Label("Import HAR file", systemImage: "square.and.arrow.down")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())

        if !store.transactions.isEmpty {
          Text(
            "\(store.transactions.count) request\(store.transactions.count == 1 ? "" : "s") currently in the trace."
          )
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(AppTheme.secondaryText)
        }
      }
    }
  }

  private func captureRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .frame(width: 22)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(AppTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func step(number: Int, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Text("\(number)")
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(AppTheme.background)
        .frame(width: 21, height: 21)
        .background(AppTheme.accent, in: Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(AppTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func limitation(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
      Text(detail)
        .font(.system(size: 10))
        .foregroundStyle(AppTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func importHAR(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      alert = AlertPayload(title: "Import failed", message: error.localizedDescription)
    case .success(let urls):
      guard let url = urls.first else { return }
      do {
        let count = try HARImport.perform(url: url, store: store)
        alert = AlertPayload(
          title: "HAR imported",
          message: "Added \(count) request\(count == 1 ? "" : "s") to the trace."
        )
      } catch {
        alert = AlertPayload(title: "Import failed", message: error.localizedDescription)
      }
    }
  }
}
