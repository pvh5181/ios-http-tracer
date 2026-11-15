//
//  BrowserView.swift
//  http-trace-tool
//

import Combine
import Foundation
import SwiftUI

#if os(iOS)
  import WebKit
#endif

struct BrowserView: View {
  let showTrace: () -> Void

  var body: some View {
    #if os(iOS)
      BrowserScreen(showTrace: showTrace)
    #else
      ContentUnavailableView(
        "Browser capture is iOS-only",
        systemImage: "safari",
        description: Text("Run the app on an iPhone or iPad to use the instrumented browser.")
      )
    #endif
  }
}

#if os(iOS)

  @MainActor
  private final class BrowserState: ObservableObject {
    private(set) var webView: WKWebView?

    @Published var address = "https://example.com"
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false

    private var hasLoadedInitialPage = false

    func attach(_ webView: WKWebView) {
      self.webView = webView
    }

    func loadInitialPageIfNeeded() {
      guard !hasLoadedInitialPage else { return }
      hasLoadedInitialPage = true
      load("https://example.com")
    }

    func load(_ rawValue: String) {
      let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }

      let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
      guard let url = URL(string: candidate),
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https"
      else { return }

      address = url.absoluteString
      webView?.load(URLRequest(url: url))
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stop() { webView?.stopLoading() }

    func updateNavigationState() {
      canGoBack = webView?.canGoBack ?? false
      canGoForward = webView?.canGoForward ?? false
      if let currentURL = webView?.url?.absoluteString, !currentURL.isEmpty {
        address = currentURL
      }
    }
  }

  private struct BrowserScreen: View {
    @EnvironmentObject private var store: TrafficStore
    let showTrace: () -> Void

    @StateObject private var browser = BrowserState()
    @State private var showingInfo = false

    var body: some View {
      NavigationStack {
        VStack(spacing: 0) {
          addressBar
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

          if browser.isLoading {
            ProgressView(value: browser.progress)
              .progressViewStyle(.linear)
              .tint(AppTheme.accent)
              .scaleEffect(x: 1, y: 0.55, anchor: .top)
          }

          BrowserWebView(state: browser, store: store)
            .background(AppTheme.background)
        }
        .background(AppTheme.background)
        .navigationTitle("Browser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              showingInfo = true
            } label: {
              Image(systemName: "info.circle")
            }
            .accessibilityLabel("Capture limitations")
          }

          ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: showTrace) {
              HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                Text("\(store.transactions.count)")
                  .font(.system(size: 10, weight: .semibold, design: .monospaced))
              }
            }
            .accessibilityLabel("Open trace")
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          bottomBar
        }
        .alert("Browser capture", isPresented: $showingInfo) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(
            "WKWebView only exposes main-page navigation requests and responses to the host app. Their headers, status, timing, and rendered page body are captured. Subresources, WebSocket frames, and requests inside other apps are not accessible because of the iOS sandbox."
          )
        }
      }
    }

    private var addressBar: some View {
      HStack(spacing: 8) {
        Group {
          if browser.address.lowercased().hasPrefix("https://") {
            Image(systemName: "lock.fill")
              .foregroundStyle(AppTheme.accent)
          } else {
            Image(systemName: "globe")
              .foregroundStyle(AppTheme.secondaryText)
          }
        }
        .font(.system(size: 10))
        .frame(width: 14)

        TextField("Enter a URL", text: $browser.address)
          .font(.system(size: 12, design: .monospaced))
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.go)
          .onSubmit {
            browser.load(browser.address)
          }

        if browser.isLoading {
          Button {
            browser.stop()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(AppTheme.secondaryText)
          }
          .buttonStyle(.plain)
        } else {
          Button {
            browser.reload()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(AppTheme.secondaryText)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 38)
      .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
      }
    }

    private var bottomBar: some View {
      HStack(spacing: 0) {
        browserButton(
          "chevron.left", label: "Back", enabled: browser.canGoBack, action: browser.goBack)
        browserButton(
          "chevron.right", label: "Forward", enabled: browser.canGoForward,
          action: browser.goForward)
        browserButton("house", label: "Home", enabled: true) {
          browser.load("https://example.com")
        }
        browserButton("arrow.clockwise", label: "Reload", enabled: true, action: browser.reload)

        Spacer()

        Button {
          store.isRecording.toggle()
        } label: {
          HStack(spacing: 5) {
            Circle()
              .fill(store.isRecording ? Color.red : Color.white.opacity(0.3))
              .frame(width: 6, height: 6)
            Text(store.isRecording ? "Capturing" : "Paused")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(
                store.isRecording ? Color.white.opacity(0.8) : AppTheme.secondaryText)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(AppTheme.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
      }
      .frame(height: 46)
      .background(.ultraThinMaterial)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(AppTheme.hairline)
          .frame(height: 0.5)
      }
    }

    private func browserButton(
      _ systemName: String,
      label: String,
      enabled: Bool,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        Image(systemName: systemName)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(
            enabled ? Color.white.opacity(0.8) : AppTheme.secondaryText.opacity(0.35)
          )
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .disabled(!enabled)
      .accessibilityLabel(label)
    }
  }

  private struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var state: BrowserState
    let store: TrafficStore

    func makeCoordinator() -> BrowserCoordinator {
      BrowserCoordinator(state: state, store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
      if let existing = state.webView {
        existing.navigationDelegate = context.coordinator
        existing.uiDelegate = context.coordinator
        context.coordinator.attach(to: existing)
        return existing
      }

      let configuration = WKWebViewConfiguration()
      configuration.defaultWebpagePreferences.allowsContentJavaScript = true
      configuration.allowsInlineMediaPlayback = true

      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.navigationDelegate = context.coordinator
      webView.uiDelegate = context.coordinator
      webView.allowsBackForwardNavigationGestures = true
      webView.isOpaque = false
      webView.backgroundColor = .clear
      webView.scrollView.backgroundColor = .clear

      state.attach(webView)
      context.coordinator.attach(to: webView)
      state.loadInitialPageIfNeeded()

      return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
      context.coordinator.store = store
      if uiView.navigationDelegate !== context.coordinator {
        uiView.navigationDelegate = context.coordinator
        uiView.uiDelegate = context.coordinator
        context.coordinator.attach(to: uiView)
      }
    }
  }

  @MainActor
  private final class BrowserCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var store: TrafficStore
    private let state: BrowserState

    private var progressObservation: NSKeyValueObservation?
    private var pendingRequest: URLRequest?
    private var pendingStartedAt: Date?
    private var pendingResponse: HTTPURLResponse?

    init(state: BrowserState, store: TrafficStore) {
      self.state = state
      self.store = store
    }

    func attach(to webView: WKWebView) {
      progressObservation = webView.observe(\.estimatedProgress, options: [.new]) {
        [weak self, weak webView] _, _ in
        Task { @MainActor in
          guard let self, let webView else { return }
          self.state.progress = webView.estimatedProgress
        }
      }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      state.isLoading = true
      state.updateNavigationState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
      state.updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      state.isLoading = false
      state.progress = 1
      state.updateNavigationState()
      finalizeCapture(in: webView)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      if navigationAction.targetFrame?.isMainFrame == true,
        let url = navigationAction.request.url,
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https"
      {
        pendingRequest = navigationAction.request
        pendingStartedAt = Date()
        pendingResponse = nil
        state.address = url.absoluteString
      }
      decisionHandler(.allow)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      if navigationResponse.isForMainFrame,
        let httpResponse = navigationResponse.response as? HTTPURLResponse
      {
        pendingResponse = httpResponse
      }
      decisionHandler(.allow)
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      state.isLoading = false
      state.updateNavigationState()
      recordFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      state.isLoading = false
      state.updateNavigationState()
      recordFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      state.isLoading = false
      state.updateNavigationState()
    }

    private func finalizeCapture(in webView: WKWebView) {
      guard let request = pendingRequest,
        let response = pendingResponse,
        let startedAt = pendingStartedAt
      else {
        resetPending()
        return
      }

      let mimeType = response.mimeType
      let shouldReadBody =
        mimeType.map {
          $0.contains("html")
            || $0.hasPrefix("text/")
            || $0.contains("json")
            || $0.contains("xml")
            || $0.contains("javascript")
        } ?? true

      guard shouldReadBody else {
        record(request: request, response: response, bodyText: nil, startedAt: startedAt)
        resetPending()
        return
      }

      let javascript: String
      if mimeType?.contains("html") == true {
        javascript = "document.documentElement ? document.documentElement.outerHTML : ''"
      } else {
        javascript = "document.body ? document.body.innerText : ''"
      }

      webView.evaluateJavaScript(javascript) { [weak self] result, _ in
        Task { @MainActor in
          guard let self else { return }
          self.record(
            request: request,
            response: response,
            bodyText: result as? String,
            startedAt: startedAt
          )
          self.resetPending()
        }
      }
    }

    private func recordFailure(_ error: Error) {
      let nsError = error as NSError
      guard nsError.code != NSURLErrorCancelled else { return }
      guard let request = pendingRequest, let startedAt = pendingStartedAt else { return }

      let requestSnapshot = Self.requestSnapshot(from: request, capturedAt: startedAt)
      let transaction = HTTPTransaction(
        startedAt: startedAt,
        duration: Date().timeIntervalSince(startedAt),
        request: requestSnapshot,
        response: nil,
        errorMessage: error.localizedDescription,
        source: .browser
      )
      store.record(transaction)
      resetPending()
    }

    private func record(
      request: URLRequest,
      response: HTTPURLResponse,
      bodyText: String?,
      startedAt: Date
    ) {
      let receivedAt = Date()
      let requestSnapshot = Self.requestSnapshot(from: request, capturedAt: startedAt)
      let mimeType = response.mimeType
      let body = bodyText.map {
        CapturedBody(data: Data($0.utf8), mimeType: mimeType)
      }
      let responseSnapshot = HTTPResponseSnapshot(
        statusCode: response.statusCode,
        headers: .from(response.allHeaderFields),
        body: body,
        mimeType: mimeType,
        expectedContentLength: response.expectedContentLength > 0
          ? response.expectedContentLength : nil,
        receivedAt: receivedAt
      )
      let transaction = HTTPTransaction(
        startedAt: startedAt,
        duration: receivedAt.timeIntervalSince(startedAt),
        request: requestSnapshot,
        response: responseSnapshot,
        errorMessage: nil,
        source: .browser
      )
      store.record(transaction)
    }

    private func resetPending() {
      pendingRequest = nil
      pendingStartedAt = nil
      pendingResponse = nil
    }

    private static func requestSnapshot(from request: URLRequest, capturedAt: Date)
      -> HTTPRequestSnapshot
    {
      let headers = [HTTPHeader].from(request.allHTTPHeaderFields ?? [:])
      let contentType = request.value(forHTTPHeaderField: "Content-Type")
      return HTTPRequestSnapshot(
        method: request.httpMethod ?? "GET",
        url: request.url?.absoluteString ?? "",
        headers: headers,
        body: request.httpBody.map { CapturedBody(data: $0, mimeType: contentType) },
        capturedAt: capturedAt
      )
    }
  }
#endif
