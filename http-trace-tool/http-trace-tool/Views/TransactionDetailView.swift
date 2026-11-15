//
//  TransactionDetailView.swift
//  http-trace-tool
//

import Foundation
import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case request = "Request"
  case response = "Response"

  var id: Self { self }
}

struct TransactionDetailView: View {
  let transaction: HTTPTransaction

  @State private var tab: DetailTab = .overview
  @State private var shareFile: ShareFile?
  @State private var alert: AlertPayload?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        hero

        Picker("Detail section", selection: $tab) {
          ForEach(DetailTab.allCases) { section in
            Text(section.rawValue).tag(section)
          }
        }
        .pickerStyle(.segmented)

        Group {
          switch tab {
          case .overview:
            overview
          case .request:
            request
          case .response:
            response
          }
        }
        .transition(.opacity)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 30)
    }
    .background(AppTheme.background)
    .navigationTitle(transaction.host)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            Clipboard.copy(transaction.request.url)
          } label: {
            Label("Copy URL", systemImage: "link")
          }

          Button {
            Clipboard.copy(transaction.curlCommand)
          } label: {
            Label("Copy as cURL", systemImage: "terminal")
          }

          Button {
            Clipboard.copy(
              transaction.response?.headers
                .map { "\($0.name): \($0.value)" }
                .joined(separator: "\n") ?? ""
            )
          } label: {
            Label("Copy response headers", systemImage: "doc.on.doc")
          }
          .disabled(transaction.response == nil)

          Divider()

          Button {
            exportEntry()
          } label: {
            Label("Share as HAR…", systemImage: "square.and.arrow.up")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .sheet(item: $shareFile) { file in
      ShareSheet(items: [file.url])
        .presentationDetents([.medium, .large])
    }
    .alert(item: $alert) { payload in
      Alert(title: Text(payload.title), message: Text(payload.message))
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top, spacing: 10) {
        MethodBadge(method: transaction.method)
        StatusPill(code: transaction.statusCode, error: transaction.errorMessage != nil)

        Spacer()

        Label(transaction.source.rawValue, systemImage: transaction.source.iconName)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(AppTheme.secondaryText)
          .lineLimit(1)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(transaction.host)
          .font(.system(size: 22, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(transaction.path)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(AppTheme.secondaryText)
          .textSelection(.enabled)
          .lineLimit(3)
      }

      HStack(spacing: 16) {
        Label(Formatters.duration(transaction.duration), systemImage: "timer")
        Label(Formatters.bytes(transaction.totalBytes), systemImage: "arrow.up.arrow.down")
        if let code = transaction.statusCode, code > 0 {
          Label(transaction.statusText, systemImage: "checkmark.seal")
        }
      }
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(AppTheme.secondaryText)
      .lineLimit(1)
    }
    .padding(16)
    .background(
      LinearGradient(
        colors: [AppTheme.cardElevated, AppTheme.card],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 18)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
    }
  }

  private var overview: some View {
    VStack(spacing: 14) {
      if transaction.method == "CONNECT" && transaction.source == .backgroundVPN {
        SectionCard(title: "Encrypted HTTPS tunnel", icon: "lock.fill") {
          Text(
            "The VPN captured the CONNECT handshake for this HTTPS host. TLS payload, inner request headers, and response headers are encrypted and cannot be read on-device. Import a HAR from a trusted MITM proxy if you need those headers."
          )
          .font(.system(size: 11))
          .foregroundStyle(AppTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let error = transaction.errorMessage {
        SectionCard(title: "Error", icon: "exclamationmark.triangle.fill") {
          Text(error)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
            .textSelection(.enabled)
        }
      }

      SectionCard(title: "Exchange", icon: "arrow.left.arrow.right") {
        VStack(spacing: 9) {
          MetadataRow(label: "Started", value: Formatters.dateTime(transaction.startedAt))
          MetadataRow(label: "Duration", value: Formatters.duration(transaction.duration))
          MetadataRow(label: "Source", value: transaction.source.rawValue)
          MetadataRow(label: "Method", value: transaction.method, monospaced: true)
          MetadataRow(label: "URL", value: transaction.request.url, monospaced: true)
        }
      }

      SectionCard(title: "Payload", icon: "shippingbox") {
        VStack(spacing: 9) {
          MetadataRow(
            label: "Request",
            value: requestBodySummary
          )
          MetadataRow(
            label: "Response",
            value: responseBodySummary
          )
          MetadataRow(
            label: "Type",
            value: BodyDecoder.contentTypeText(
              transaction.response?.mimeType
                ?? transaction.response?.body?.mimeType
            )
          )
        }
      }

      SectionCard(title: "Timing", icon: "clock") {
        VStack(spacing: 9) {
          MetadataRow(label: "Start", value: Formatters.time(transaction.startedAt))
          if let receivedAt = transaction.response?.receivedAt {
            MetadataRow(label: "Received", value: Formatters.time(receivedAt))
          }
          MetadataRow(label: "Elapsed", value: Formatters.duration(transaction.duration))
        }
      }
    }
  }

  private var request: some View {
    VStack(spacing: 14) {
      SectionCard(title: "Request line", icon: "arrow.up.right") {
        VStack(spacing: 9) {
          MetadataRow(label: "Method", value: transaction.method, monospaced: true)
          MetadataRow(label: "URL", value: transaction.request.url, monospaced: true)
          MetadataRow(label: "Captured", value: Formatters.dateTime(transaction.request.capturedAt))
        }
      }

      SectionCard(title: "Request headers", icon: "list.bullet.rectangle") {
        VStack(alignment: .leading, spacing: 10) {
          if !transaction.request.headers.isEmpty {
            Button {
              Clipboard.copy(copyableHeaders(transaction.request.headers))
            } label: {
              Label("Copy all", systemImage: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
          }

          HeaderList(
            headers: transaction.request.headers,
            emptyText: "No request headers were captured."
          )
        }
      }

      SectionCard(title: "Request body", icon: "curlybraces") {
        BodyInspector(
          body: transaction.request.body,
          emptyText: "This request has no body."
        )
      }
    }
  }

  private var response: some View {
    VStack(spacing: 14) {
      SectionCard(title: "Response", icon: "arrow.down.left") {
        VStack(spacing: 9) {
          if let code = transaction.statusCode {
            MetadataRow(
              label: "Status",
              value: "\(code) \(transaction.statusText)",
              monospaced: true
            )
          } else {
            MetadataRow(label: "Status", value: "No response")
          }
          MetadataRow(
            label: "Content type",
            value: BodyDecoder.contentTypeText(
              transaction.response?.mimeType
                ?? transaction.response?.body?.mimeType
            )
          )
          MetadataRow(
            label: "Body size",
            value: Formatters.bytes(transaction.response?.body?.totalByteCount ?? 0)
          )
          MetadataRow(
            label: "Received",
            value: transaction.response.map { Formatters.dateTime($0.receivedAt) } ?? "—"
          )
        }
      }

      if let error = transaction.errorMessage {
        SectionCard(title: "Error", icon: "exclamationmark.triangle.fill") {
          Text(error)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
            .textSelection(.enabled)
        }
      }

      SectionCard(title: "Response headers", icon: "list.bullet.rectangle") {
        VStack(alignment: .leading, spacing: 10) {
          if let headers = transaction.response?.headers, !headers.isEmpty {
            Button {
              Clipboard.copy(copyableHeaders(headers))
            } label: {
              Label("Copy all", systemImage: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
          }

          HeaderList(
            headers: transaction.response?.headers ?? [],
            emptyText: "No response headers were captured."
          )
        }
      }

      SectionCard(title: "Response body", icon: "curlybraces") {
        BodyInspector(
          body: transaction.response?.body,
          emptyText: transaction.response == nil
            ? "The request did not receive a response."
            : "This response has no body. (It may have been large, empty, or encoded in a way the browser did not expose.)"
        )
      }
    }
  }

  private var requestBodySummary: String {
    guard let body = transaction.request.body else { return "None" }
    return "\(Formatters.bytes(body.totalByteCount)) · \(body.mimeType ?? "unknown type")"
  }

  private var responseBodySummary: String {
    guard let body = transaction.response?.body else { return "None" }
    return "\(Formatters.bytes(body.totalByteCount)) · \(body.mimeType ?? "unknown type")"
  }

  private func copyableHeaders(_ headers: [HTTPHeader]) -> String {
    headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
  }

  private func exportEntry() {
    do {
      let url = try HARCodec.exportURL(transactions: [transaction])
      shareFile = ShareFile(url: url)
    } catch {
      alert = AlertPayload(title: "Export failed", message: error.localizedDescription)
    }
  }
}

extension HTTPTransaction {
  fileprivate var curlCommand: String {
    var parts = ["curl -X \(method) '\(request.url.replacingOccurrences(of: "'", with: "'\\''"))'"]
    for header in request.headers {
      let value = header.value.replacingOccurrences(of: "'", with: "'\\''")
      parts.append("-H '\(header.name): \(value)'")
    }
    if let body = request.body,
      let text = String(data: body.data, encoding: .utf8),
      BodyDecoder.isText(mimeType: body.mimeType, data: body.data)
    {
      let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
      parts.append("--data-raw '\(escaped)'")
    }
    return parts.joined(separator: " \\\n  ")
  }
}
