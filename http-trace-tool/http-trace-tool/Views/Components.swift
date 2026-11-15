//
//  Components.swift
//  http-trace-tool
//

import Foundation
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

struct AlertPayload: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

struct MethodBadge: View {
  let method: String

  var body: some View {
    Text(method.uppercased())
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .tracking(0.5)
      .foregroundStyle(AppTheme.methodColor(method))
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(AppTheme.methodColor(method).opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
      .overlay {
        RoundedRectangle(cornerRadius: 5)
          .strokeBorder(AppTheme.methodColor(method).opacity(0.24), lineWidth: 0.5)
      }
  }
}

struct StatusPill: View {
  let code: Int?
  let error: Bool

  private var color: Color {
    error ? Color(red: 1.0, green: 0.42, blue: 0.46) : AppTheme.statusColor(code)
  }

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 5, height: 5)
      Text(code.map(String.init) ?? "ERR")
        .font(.system(size: 11, weight: .bold, design: .monospaced))
    }
    .foregroundStyle(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(color.opacity(0.11), in: Capsule())
  }
}

struct StatTile: View {
  let title: String
  let value: String
  let icon: String
  var tint: Color = AppTheme.accent

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
        Spacer()
      }
      .foregroundStyle(tint)

      Text(value)
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AppTheme.secondaryText)
        .textCase(.uppercase)
        .tracking(0.5)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 13))
    .overlay {
      RoundedRectangle(cornerRadius: 13)
        .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
    }
  }
}

struct FilterChip: View {
  let title: String
  let count: Int?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Text(title)
        if let count {
          Text("\(count)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(isSelected ? AppTheme.background : AppTheme.secondaryText)
        }
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(isSelected ? AppTheme.background : Color.white.opacity(0.75))
      .padding(.horizontal, 11)
      .padding(.vertical, 7)
      .background(isSelected ? AppTheme.accent : AppTheme.card, in: Capsule())
      .overlay {
        if !isSelected {
          Capsule().strokeBorder(AppTheme.hairline, lineWidth: 0.5)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

struct SectionCard<Content: View>: View {
  let title: String?
  let icon: String?
  @ViewBuilder let content: Content

  init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.icon = icon
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let title {
        HStack(spacing: 6) {
          if let icon {
            Image(systemName: icon)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(AppTheme.accent)
          }
          Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .textCase(.uppercase)
            .tracking(0.6)
        }
      }
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
    }
  }
}

struct MetadataRow: View {
  let label: String
  let value: String
  var monospaced = false

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(width: 78, alignment: .leading)
      Text(value)
        .font(
          .system(
            size: 12, weight: monospaced ? .regular : .medium,
            design: monospaced ? .monospaced : .default)
        )
        .foregroundStyle(.white.opacity(0.88))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct HeaderList: View {
  let headers: [HTTPHeader]
  let emptyText: String
  @State private var copiedHeader: UUID?

  var body: some View {
    if headers.isEmpty {
      Text(emptyText)
        .font(.system(size: 12))
        .foregroundStyle(AppTheme.secondaryText)
    } else {
      VStack(spacing: 0) {
        ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
          if index > 0 {
            Divider().overlay(AppTheme.hairline)
          }
          HStack(alignment: .top, spacing: 10) {
            Text(header.name)
              .font(.system(size: 11, weight: .semibold, design: .monospaced))
              .foregroundStyle(AppTheme.accent.opacity(0.9))
              .frame(width: 118, alignment: .leading)
              .textSelection(.enabled)

            Text(header.value)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.white.opacity(0.82))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            Button {
              Clipboard.copy("\(header.name): \(header.value)")
              copiedHeader = header.id
              Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if copiedHeader == header.id { copiedHeader = nil }
              }
            } label: {
              Image(systemName: copiedHeader == header.id ? "checkmark" : "doc.on.doc")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                  copiedHeader == header.id ? AppTheme.accent : AppTheme.secondaryText)
            }
            .buttonStyle(.plain)
          }
          .padding(.vertical, 7)
        }
      }
    }
  }
}

struct BodyInspector: View {
  let payload: CapturedBody?
  let emptyText: String

  init(body: CapturedBody?, emptyText: String) {
    self.payload = body
    self.emptyText = emptyText
  }

  @State private var showRaw = false
  @State private var copied = false

  private var isImage: Bool {
    guard let payload,
      let mime = payload.mimeType?.lowercased(),
      mime.hasPrefix("image/")
    else { return false }
    return platformImage(from: payload.data) != nil
  }

  private var isText: Bool {
    guard let payload else { return false }
    return BodyDecoder.isText(mimeType: payload.mimeType, data: payload.data)
  }

  private var isJSON: Bool {
    guard let payload else { return false }
    return BodyDecoder.isJSON(mimeType: payload.mimeType, data: payload.data)
  }

  private var previewData: Data {
    guard let payload else { return Data() }
    if payload.data.count > CaptureLimits.maxPreviewBytes {
      return Data(payload.data.prefix(CaptureLimits.maxPreviewBytes))
    }
    return payload.data
  }

  private var isPreviewCapped: Bool {
    (payload?.data.count ?? 0) > CaptureLimits.maxPreviewBytes
  }

  private var displayText: String {
    guard payload != nil else { return "" }
    if isJSON, !showRaw, let pretty = BodyDecoder.prettyJSON(from: previewData) {
      return pretty
    }
    if isText {
      return BodyDecoder.text(from: previewData, mimeType: payload?.mimeType)
    }
    return BodyDecoder.hexDump(previewData)
  }

  private var copyText: String {
    guard let payload else { return "" }
    if isJSON, let pretty = BodyDecoder.prettyJSON(from: payload.data) {
      return pretty
    }
    if isText {
      return BodyDecoder.text(from: payload)
    }
    return BodyDecoder.hexDump(payload.data)
  }

  var body: some View {
    if let payload, !payload.data.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Text(payload.mimeType ?? "application/octet-stream")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.secondaryText)
            .lineLimit(1)

          Text(Formatters.bytes(payload.totalByteCount))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppTheme.secondaryText.opacity(0.8))

          Spacer()

          if isJSON {
            Button(showRaw ? "Pretty" : "Raw") {
              showRaw.toggle()
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
          }

          Button {
            Clipboard.copy(copyText)
            copied = true
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1.2))
              copied = false
            }
          } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(copied ? AppTheme.accent : AppTheme.secondaryText)
          }
          .buttonStyle(.plain)
        }

        if isImage, let image = platformImage(from: payload.data) {
          imageView(image)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          ScrollView(.horizontal, showsIndicators: true) {
            Text(displayText)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.white.opacity(0.88))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(AppTheme.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
        }

        if payload.isTruncated {
          Label(
            "Body capped at \(Formatters.bytes(payload.data.count)) of \(Formatters.bytes(payload.totalByteCount))",
            systemImage: "scissors"
          )
          .font(.system(size: 10))
          .foregroundStyle(Color.orange.opacity(0.85))
        }
      }
    } else {
      HStack(spacing: 7) {
        Image(systemName: "tray")
          .font(.system(size: 11))
        Text(emptyText)
          .font(.system(size: 12))
      }
      .foregroundStyle(AppTheme.secondaryText)
      .padding(.vertical, 4)
    }
  }

  @ViewBuilder
  private func imageView(_ image: PlatformImage) -> some View {
    #if canImport(UIKit)
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxHeight: 280)
    #elseif canImport(AppKit)
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxHeight: 280)
    #endif
  }
}

#if canImport(UIKit)
  typealias PlatformImage = UIImage
  private func platformImage(from data: Data) -> PlatformImage? {
    UIImage(data: data)
  }
#elseif canImport(AppKit)
  typealias PlatformImage = NSImage
  private func platformImage(from data: Data) -> PlatformImage? {
    NSImage(data: data)
  }
#endif

struct ShareSheet: View {
  let items: [Any]

  var body: some View {
    #if canImport(UIKit)
      ActivityViewController(items: items)
    #else
      EmptyView()
    #endif
  }
}

#if canImport(UIKit)
  private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
      UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
  }
#endif

struct ShareFile: Identifiable {
  let id = UUID()
  let url: URL
}
