//
//  TrafficListView.swift
//  http-trace-tool
//

import Foundation
import SwiftUI

private enum TraceFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case errors = "Errors"
  case get = "GET"
  case post = "POST"
  case vpn = "VPN"
  case imported = "Imported"

  var id: Self { self }

  func matches(_ transaction: HTTPTransaction) -> Bool {
    switch self {
    case .all: true
    case .errors: transaction.isError
    case .get: transaction.method == "GET"
    case .post: transaction.method == "POST"
    case .vpn: transaction.source == .backgroundVPN
    case .imported: transaction.source == .imported
    }
  }
}

struct TrafficListView: View {
  @EnvironmentObject private var store: TrafficStore
  @EnvironmentObject private var vpn: BackgroundVPNController
  let openBrowser: () -> Void
  let openRequestLab: () -> Void

  @State private var searchText = ""
  @State private var filter: TraceFilter = .all
  @State private var showingImporter = false
  @State private var showingClearConfirmation = false
  @State private var shareFile: ShareFile?
  @State private var alert: AlertPayload?

  private var filteredTransactions: [HTTPTransaction] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return store.transactions.filter { transaction in
      guard filter.matches(transaction) else { return false }
      return query.isEmpty || transaction.searchableText.contains(query)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0) {
          summaryHeader
            .padding(.bottom, 12)

          if filteredTransactions.isEmpty {
            emptyState
              .padding(.top, store.transactions.isEmpty ? 18 : 24)
          } else {
            ForEach(filteredTransactions) { transaction in
              NavigationLink(value: transaction) {
                TransactionRow(transaction: transaction)
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button {
                  Clipboard.copy(transaction.request.url)
                } label: {
                  Label("Copy URL", systemImage: "link")
                }

                Button {
                  store.remove(transaction)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }

              if transaction.id != filteredTransactions.last?.id {
                Divider()
                  .overlay(AppTheme.hairline)
                  .padding(.leading, 62)
              }
            }
            .padding(.horizontal, 16)

            Text("\(filteredTransactions.count) of \(store.transactions.count) requests")
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(AppTheme.secondaryText)
              .padding(.vertical, 18)
          }
        }
      }
      .background(AppTheme.background)
      .navigationTitle("HTTP Trace")
      .searchable(text: $searchText, prompt: "Search URL, headers, body")
      .navigationDestination(for: HTTPTransaction.self) { transaction in
        TransactionDetailView(transaction: transaction)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            store.isRecording.toggle()
          } label: {
            Image(systemName: store.isRecording ? "record.circle.fill" : "pause.circle")
              .foregroundStyle(store.isRecording ? Color.red : AppTheme.secondaryText)
          }
          .accessibilityLabel(store.isRecording ? "Pause capture" : "Resume capture")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            showingImporter = true
          } label: {
            Image(systemName: "square.and.arrow.down")
          }
          .accessibilityLabel("Import HAR")

          Menu {
            Button {
              showingImporter = true
            } label: {
              Label("Import HAR…", systemImage: "square.and.arrow.down")
            }

            Button {
              exportHAR()
            } label: {
              Label("Export all as HAR…", systemImage: "square.and.arrow.up")
            }
            .disabled(store.transactions.isEmpty)

            Divider()

            Button(role: .destructive) {
              showingClearConfirmation = true
            } label: {
              Label("Clear trace", systemImage: "trash")
            }
            .disabled(store.transactions.isEmpty)
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .fileImporter(
        isPresented: $showingImporter,
        allowedContentTypes: HARFileTypes.allowed,
        allowsMultipleSelection: false
      ) { result in
        importHAR(result)
      }
      .sheet(item: $shareFile) { file in
        ShareSheet(items: [file.url])
          .presentationDetents([.medium, .large])
      }
      .confirmationDialog(
        "Clear all captured traffic?",
        isPresented: $showingClearConfirmation,
        titleVisibility: .visible
      ) {
        Button("Clear trace", role: .destructive) {
          store.clear()
        }
        Button("Cancel", role: .cancel) {}
      }
      .alert(item: $alert) { payload in
        Alert(title: Text(payload.title), message: Text(payload.message))
      }
    }
  }

  private var summaryHeader: some View {
    VStack(spacing: 12) {
      backgroundCaptureCard

      if !store.transactions.isEmpty {
        liveCaptureCard
        statsGrid
        filterBar
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }

  private var backgroundCaptureCard: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 10)
            .fill(
              vpn.isActive
                ? AppTheme.accent.opacity(0.15)
                : Color.white.opacity(0.06)
            )
            .frame(width: 36, height: 36)
          Image(systemName: "shield.lefthalf.filled")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(vpn.isActive ? AppTheme.accent : AppTheme.secondaryText)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("Background capture")
            .font(.system(size: 13, weight: .semibold))
          Text(
            vpn.isActive
              ? "Other apps' HTTP traffic is being recorded."
              : "Capture other apps while HTTP Trace is closed."
          )
          .font(.system(size: 10))
          .foregroundStyle(AppTheme.secondaryText)
          .lineLimit(2)
        }

        Spacer(minLength: 4)

        if vpn.isBusy {
          ProgressView()
            .controlSize(.small)
            .tint(AppTheme.accent)
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
                vpn.isActive ? Color.white.opacity(0.1) : AppTheme.accent,
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
          .disabled(vpn.isBusy)
        }
      }

      HStack(spacing: 6) {
        Circle()
          .fill(vpn.isActive ? AppTheme.accent : AppTheme.secondaryText.opacity(0.5))
          .frame(width: 6, height: 6)
        Text(vpn.statusText)
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .foregroundStyle(vpn.isActive ? AppTheme.accent : AppTheme.secondaryText)
        Spacer()
        Text("HTTP headers · HTTPS host metadata")
          .font(.system(size: 9))
          .foregroundStyle(AppTheme.secondaryText.opacity(0.8))
      }

      if let error = vpn.errorMessage {
        Text(error)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .background(
      LinearGradient(
        colors: vpn.isActive
          ? [AppTheme.accent.opacity(0.12), AppTheme.card]
          : [AppTheme.cardElevated, AppTheme.card],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 16)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(
          vpn.isActive ? AppTheme.accent.opacity(0.3) : AppTheme.hairline,
          lineWidth: 0.5
        )
    }
  }

  private var liveCaptureCard: some View {
    HStack(spacing: 9) {
      ZStack {
        Circle()
          .fill(store.isRecording ? Color.red.opacity(0.15) : Color.white.opacity(0.07))
          .frame(width: 26, height: 26)
        Image(systemName: store.isRecording ? "record.circle.fill" : "pause.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(store.isRecording ? Color.red : AppTheme.secondaryText)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(store.isRecording ? "Live capture" : "Capture paused")
          .font(.system(size: 13, weight: .semibold))
        Text("URLSession + browser navigations")
          .font(.system(size: 10))
          .foregroundStyle(AppTheme.secondaryText)
      }

      Spacer()

      Button {
        store.isRecording.toggle()
      } label: {
        Text(store.isRecording ? "Pause" : "Resume")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(AppTheme.accent)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(AppTheme.accent.opacity(0.1), in: Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
    }
  }

  private var statsGrid: some View {
    HStack(spacing: 8) {
      StatTile(
        title: "Requests",
        value: "\(store.stats.requestCount)",
        icon: "arrow.up.arrow.down"
      )
      StatTile(
        title: "Errors",
        value: "\(store.stats.errorCount)",
        icon: "exclamationmark.triangle",
        tint: store.stats.errorCount == 0 ? AppTheme.accent : Color.orange
      )
      StatTile(
        title: "Transferred",
        value: Formatters.bytes(store.stats.byteCount),
        icon: "internaldrive"
      )
      StatTile(
        title: "Avg. time",
        value: Formatters.duration(store.stats.averageDuration),
        icon: "timer",
        tint: Color(red: 0.55, green: 0.65, blue: 1.0)
      )
    }
  }

  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 7) {
        ForEach(TraceFilter.allCases) { option in
          FilterChip(
            title: option.rawValue,
            count: count(for: option),
            isSelected: filter == option
          ) {
            withAnimation(.snappy(duration: 0.18)) {
              filter = option
            }
          }
        }
      }
      .padding(.horizontal, 1)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 22) {
      ZStack {
        Circle()
          .fill(AppTheme.accent.opacity(0.08))
          .frame(width: 92, height: 92)
        Image(systemName: store.transactions.isEmpty ? "waveform.path.ecg" : "magnifyingglass")
          .font(.system(size: 34, weight: .light))
          .foregroundStyle(AppTheme.accent)
      }

      VStack(spacing: 7) {
        Text(store.transactions.isEmpty ? "No traffic captured yet" : "No matching requests")
          .font(.system(size: 20, weight: .semibold, design: .rounded))
        Text(
          store.transactions.isEmpty
            ? "Start background capture to see other apps, or browse a page and compose a request. Headers, bodies, and timing land here."
            : "Try another search term or filter."
        )
        .font(.system(size: 13))
        .foregroundStyle(AppTheme.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 330)
      }

      if store.transactions.isEmpty {
        HStack(spacing: 10) {
          Button(action: openBrowser) {
            Label("Open browser", systemImage: "safari")
          }
          .buttonStyle(PrimaryButtonStyle())

          Button(action: openRequestLab) {
            Label("Compose", systemImage: "paperplane")
          }
          .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 24)

        Button {
          showingImporter = true
        } label: {
          Text("or import a HAR file")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.accent)
        }
        .buttonStyle(.plain)
        .padding(.top, -8)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 30)
  }

  private func count(for filter: TraceFilter) -> Int? {
    switch filter {
    case .all: store.transactions.count
    case .errors: store.transactions.filter(\.isError).count
    case .get: store.transactions.filter { $0.method == "GET" }.count
    case .post: store.transactions.filter { $0.method == "POST" }.count
    case .vpn: store.transactions.filter { $0.source == .backgroundVPN }.count
    case .imported: store.transactions.filter { $0.source == .imported }.count
    }
  }

  private func exportHAR() {
    do {
      let url = try HARCodec.exportURL(transactions: store.transactions)
      shareFile = ShareFile(url: url)
    } catch {
      alert = AlertPayload(title: "Export failed", message: error.localizedDescription)
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

struct TransactionRow: View {
  let transaction: HTTPTransaction

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      MethodBadge(method: transaction.method)
        .frame(width: 52, alignment: .leading)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(transaction.host)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)

          Spacer(minLength: 6)

          StatusPill(code: transaction.statusCode, error: transaction.errorMessage != nil)
        }

        Text(transaction.path)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(AppTheme.secondaryText)
          .lineLimit(1)

        HStack(spacing: 7) {
          Image(systemName: transaction.source.iconName)
            .font(.system(size: 8, weight: .semibold))
          Text(transaction.source.rawValue)
          Text("·")
          Text(Formatters.compactDateTime(transaction.startedAt))
          Text("·")
          Text(Formatters.duration(transaction.duration))
          Spacer()
          Text(Formatters.bytes(transaction.totalBytes))
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(AppTheme.secondaryText.opacity(0.8))
      }
    }
    .padding(.vertical, 11)
    .contentShape(Rectangle())
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(AppTheme.background)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(AppTheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
  }
}

struct SecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(Color.white.opacity(0.85))
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(AppTheme.cardElevated.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
      .overlay {
        Capsule().strokeBorder(AppTheme.hairline, lineWidth: 0.5)
      }
  }
}
