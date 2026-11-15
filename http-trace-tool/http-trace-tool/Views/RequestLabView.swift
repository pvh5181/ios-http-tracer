//
//  RequestLabView.swift
//  http-trace-tool
//

import Foundation
import SwiftUI

private struct EditableHeader: Identifiable, Hashable {
  let id = UUID()
  var name: String
  var value: String
}

private struct RequestResult {
  let statusCode: Int?
  let duration: TimeInterval
  let byteCount: Int
  let error: String?
}

struct RequestLabView: View {
  @EnvironmentObject private var store: TrafficStore
  let showTrace: () -> Void

  @State private var urlString = "https://httpbin.org/anything"
  @State private var method = "GET"
  @State private var headers: [EditableHeader] = [
    EditableHeader(name: "Accept", value: "application/json")
  ]
  @State private var bodyText = ""
  @State private var isSending = false
  @State private var result: RequestResult?
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case url
    case body
  }

  private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

  private var supportsBody: Bool {
    !["GET", "HEAD"].contains(method)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          intro

          SectionCard(title: "Destination", icon: "link") {
            VStack(spacing: 10) {
              HStack(spacing: 9) {
                Menu {
                  ForEach(methods, id: \.self) { option in
                    Button(option) {
                      method = option
                    }
                  }
                } label: {
                  HStack(spacing: 5) {
                    Text(method)
                      .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Image(systemName: "chevron.up.chevron.down")
                      .font(.system(size: 8, weight: .bold))
                  }
                  .foregroundStyle(AppTheme.methodColor(method))
                  .padding(.horizontal, 10)
                  .frame(height: 40)
                  .background(
                    AppTheme.methodColor(method).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9))
                }

                TextField("https://example.com/api", text: $urlString)
                  .font(.system(size: 12, design: .monospaced))
                  .keyboardType(.URL)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .focused($focusedField, equals: .url)
                  .submitLabel(.send)
                  .onSubmit(send)
                  .padding(.horizontal, 11)
                  .frame(height: 40)
                  .background(
                    AppTheme.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 9)
                  )
                  .overlay {
                    RoundedRectangle(cornerRadius: 9)
                      .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
                  }
              }

              HStack(spacing: 6) {
                Text("Recent preset:")
                  .font(.system(size: 10))
                  .foregroundStyle(AppTheme.secondaryText)
                presetButton("httpbin /headers", url: "https://httpbin.org/headers")
                presetButton("JSONPlaceholder", url: "https://jsonplaceholder.typicode.com/posts/1")
                Spacer()
              }
            }
          }

          SectionCard(title: "Headers", icon: "list.bullet.rectangle") {
            VStack(spacing: 8) {
              ForEach($headers) { $header in
                HStack(spacing: 7) {
                  TextField("Header", text: $header.name)
                    .font(.system(size: 11, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 130)
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background(
                      AppTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))

                  TextField("Value", text: $header.value)
                    .font(.system(size: 11, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background(
                      AppTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))

                  Button {
                    headers.removeAll { $0.id == header.id }
                  } label: {
                    Image(systemName: "minus.circle")
                      .font(.system(size: 13))
                      .foregroundStyle(AppTheme.secondaryText)
                  }
                  .buttonStyle(.plain)
                }
              }

              Button {
                headers.append(EditableHeader(name: "", value: ""))
              } label: {
                Label("Add header", systemImage: "plus")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(AppTheme.accent)
              }
              .buttonStyle(.plain)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          if supportsBody {
            SectionCard(title: "Body", icon: "curlybraces") {
              ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                  Text("{\n  \"key\": \"value\"\n}")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.45))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $bodyText)
                  .font(.system(size: 11, design: .monospaced))
                  .scrollContentBackground(.hidden)
                  .focused($focusedField, equals: .body)
                  .padding(7)
                  .frame(minHeight: 130)
              }
              .background(AppTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
              .overlay {
                RoundedRectangle(cornerRadius: 9)
                  .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
              }

              if !bodyText.isEmpty {
                HStack {
                  Text("Content-Type is sent as application/json unless you add your own.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.secondaryText)
                  Spacer()
                  Text(Formatters.bytes(bodyText.utf8.count))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText)
                }
              }
            }
          }

          Button(action: send) {
            HStack {
              if isSending {
                ProgressView()
                  .tint(AppTheme.background)
                  .scaleEffect(0.8)
              } else {
                Image(systemName: "paperplane.fill")
              }
              Text(isSending ? "Sending…" : "Send request")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(isSending || URL(string: normalizedURLString) == nil)
          .opacity(isSending || URL(string: normalizedURLString) == nil ? 0.5 : 1)

          if let result {
            resultCard(result)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }

          Text(
            "Requests are sent through the app's instrumented URLSession, so the full exchange appears in Trace."
          )
          .font(.system(size: 10))
          .foregroundStyle(AppTheme.secondaryText)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 30)
      }
      .background(AppTheme.background)
      .navigationTitle("Compose")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: showTrace) {
            Image(systemName: "list.bullet.rectangle")
          }
          .accessibilityLabel("Open trace")
        }
      }
      .animation(.snappy(duration: 0.22), value: result?.statusCode)
      .animation(.snappy(duration: 0.22), value: result?.error)
    }
  }

  private var intro: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(AppTheme.accent.opacity(0.11))
          .frame(width: 42, height: 42)
        Image(systemName: "square.and.pencil")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(AppTheme.accent)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text("Build a request. Inspect every byte.")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
        Text(
          "Use arbitrary methods, headers, and bodies. Each send is captured with the exact request and response headers."
        )
        .font(.system(size: 11))
        .foregroundStyle(AppTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
    }
  }

  private func presetButton(_ title: String, url: String) -> some View {
    Button {
      urlString = url
    } label: {
      Text(title)
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(AppTheme.accent.opacity(0.9))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppTheme.accent.opacity(0.08), in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private func resultCard(_ result: RequestResult) -> some View {
    SectionCard(
      title: "Last response",
      icon: result.error == nil ? "checkmark.circle" : "exclamationmark.triangle"
    ) {
      VStack(alignment: .leading, spacing: 10) {
        if let error = result.error {
          Text(error)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
            .textSelection(.enabled)
        } else {
          HStack(spacing: 10) {
            StatusPill(code: result.statusCode, error: false)
            Text(result.statusCode.map(HTTPStatusText.text(for:)) ?? "Response")
              .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(Formatters.duration(result.duration))
            Text(Formatters.bytes(result.byteCount))
          }
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(AppTheme.secondaryText)
        }

        Button(action: showTrace) {
          Label("Open in Trace", systemImage: "arrow.up.right.square")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var normalizedURLString: String {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains("://") { return trimmed }
    return "https://\(trimmed)"
  }

  private func send() {
    guard !isSending,
      let url = URL(string: normalizedURLString),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return }

    focusedField = nil
    isSending = true
    result = nil

    var request = URLRequest(url: url)
    request.httpMethod = method

    for header in headers {
      let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let value = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      request.setValue(value, forHTTPHeaderField: name)
    }

    if supportsBody, !bodyText.isEmpty {
      request.httpBody = Data(bodyText.utf8)
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }

    let startedAt = Date()

    Task {
      do {
        let (data, response) = try await InstrumentedSession.data(for: request, source: .requestLab)
        let httpResponse = response as? HTTPURLResponse
        let elapsed = Date().timeIntervalSince(startedAt)
        result = RequestResult(
          statusCode: httpResponse?.statusCode,
          duration: elapsed,
          byteCount: data.count,
          error: nil
        )
      } catch {
        result = RequestResult(
          statusCode: nil,
          duration: Date().timeIntervalSince(startedAt),
          byteCount: 0,
          error: error.localizedDescription
        )
      }
      isSending = false
    }
  }
}
