# HTTP Trace

A native SwiftUI iPhone/iPad HTTP inspector with an optional **background VPN**
for capturing traffic from other apps.

## What it captures

| Mode | Background | What you get |
| --- | --- | --- |
| **Background VPN** | Yes, while the VPN is enabled | Plain-HTTP request/response headers, bodies, status, and timing from apps that use the system HTTP proxy. HTTPS appears as `CONNECT host:port` metadata. |
| **Request Lab** | App must be active | Complete request/response exchange for arbitrary requests. |
| **In-app browser** | App must be active | Main-page navigation request/response headers, status, timing, and rendered body. |
| **Instrumented URLSession** | App must be active | Any app code routed through `InstrumentedSession`. |
| **HAR import** | N/A | Whole-device captures from Proxyman, Charles, mitmproxy, Chrome DevTools, etc. |

### The HTTPS limitation

iOS does not give an app the TLS session keys for another app. The background
VPN therefore sees HTTPS as an opaque `CONNECT` tunnel: host and port are
visible, but inner request/response headers and bodies are encrypted.

To inspect HTTPS headers, route the device through a trusted MITM proxy on a
computer, install/trust its CA, export a HAR, and import it here. The **Guide**
tab walks through the process. Certificate-pinned apps will still reject a MITM
proxy.

## Features

- Background VPN capture from other apps while HTTP Trace is closed
- Live trace list with request/error counts, transferred bytes, average time
- Search across URL, headers, request body, response body, and error text
- Filters for errors, GET, POST, VPN, and imported traffic
- Pause/resume capture (including background capture), delete entries, clear
- Request/response detail:
  - Status, duration, timestamps, source, MIME type
  - All captured headers with per-header and copy-all actions
  - JSON pretty-printing, raw text, hex dump, image preview
  - Copy as cURL and copy URL
- Custom request composer with method, headers, and body editor
- Embedded WKWebView browser
- HAR 1.2 import and export
- No third-party dependencies

## Background VPN architecture

```
Other app
   │  system HTTP proxy (set by NEProxySettings)
   ▼
127.0.0.1 dynamic port            HTTPTraceTunnel.appex
   │                              ├─ HTTP: parse, forward, capture
   ▼                              └─ HTTPS: CONNECT, blind byte relay
HTTPProxyServer
   │
   ├─ writes one-entry HAR files to an App Group
   ▼
HTTP Trace app drains them when active / every 2s in foreground
```

- `PacketTunnelProvider` installs `NEProxySettings` for HTTP and HTTPS and keeps
  the extension alive in the background.
- The tunnel has **no IP routes**; it exists to apply the system proxy without
  taking over raw packet traffic. Ordinary sockets that ignore the system proxy
  are not captured.
- `HTTPProxyServer` listens on a dynamic loopback port, so only the device can
  reach it.
- Captures are written as HAR files to the App Group
  `group.itsover.http-trace-tool`, then imported into the live trace by the app.
  Background bodies are capped at 512 KB, and the queue is capped at 5,000
  files (oldest first out) to bound disk use.
- The app's own URLSession/browser captures are preferred over duplicate VPN
  entries for the same exchange.

## Signing and setup (required for background capture)

The background tunnel is a real Network Extension and cannot run with a normal
free provisioning profile.

1. Open `http-trace-tool.xcodeproj`.
2. Select your development team for **both** the `http-trace-tool` and
   `HTTPTraceTunnel` targets.
3. Register/verify these identifiers in the Apple Developer portal:
   - App Group: `group.itsover.http-trace-tool`
   - App ID: `itsover.http-trace-tool`
   - Extension App ID: `itsover.http-trace-tool.tunnel`
4. Enable **Network Extensions** (Packet Tunnel Provider) and **App Groups** for
   both App IDs.
5. Build and run on a physical device.
6. Tap **Start** on the Background capture card and approve the VPN prompt.

The entitlements live in `Config/`. If you change bundle identifiers, update the
App Group and the extension bundle identifier consistently. The app derives the
provider bundle ID from its own bundle ID by appending `.tunnel`.

Without the entitlements/profile, iOS rejects the VPN configuration and the app
shows the error inline. This is expected.

## Build

Requirements:

- Xcode 16+ (created with Xcode 26)
- iOS 17.0+
- Paid Apple Developer account with Network Extensions + App Groups for the VPN

Open `http-trace-tool.xcodeproj`, choose the `http-trace-tool` scheme, select a
device, and run.

The app intentionally enables `NSAllowsArbitraryLoads` because this is a
diagnostic tool that must inspect plain HTTP endpoints. Remove that ATS
exception before shipping a production build.

## Privacy and safety

- Captured headers and bodies can contain cookies, tokens, and other secrets.
  Exported HAR files are unencrypted.
- The background proxy binds to loopback only.
- The app never bypasses TLS validation. HTTPS interception only works through a
  proxy whose CA the user deliberately installs and trusts.
- The VPN must be started by the user and can be stopped from the app or iOS
  Settings.

## Layout

```
http-trace-tool/                 SwiftUI app
├── Capture/
│   ├── BackgroundVPNController.swift  NETunnelProviderManager lifecycle
│   ├── InstrumentedSession.swift      URLSession wired to the recorder
│   ├── TrafficStore.swift             Live trace state + App Group draining
│   └── TrafficURLProtocol.swift       In-app request/response capture
├── Views/                         Trace, detail, composer, browser, guide
├── Utilities/
Shared/                          Shared by app + extension
├── HTTPTransaction.swift
├── HAR.swift
├── Formatting.swift
└── BackgroundCapturePaths.swift
HTTPTraceTunnel/                 Network Extension
├── PacketTunnelProvider.swift   VPN + NEProxySettings
├── HTTPProxyServer.swift        Loopback listener
├── HTTPProxyConnection.swift    HTTP forwarding + CONNECT relay
└── HTTPMessageParser.swift      Request/response framing
Config/                          Entitlements + extension Info.plist
Artwork/                         Source app icon
```

## Verification

- The app and extension build successfully with `xcodebuild` for the iOS 17+
  device target with code signing disabled.
- The HAR codec was round-trip tested.
- The URLProtocol recorder was tested against `https://example.com/`.
- The background proxy was tested end-to-end on macOS:
  - Plain HTTP through the proxy captured request/response headers and body.
  - HTTPS `CONNECT` through the proxy tunneled successfully and was recorded.
- HTTP framing tests cover Content-Length, chunked bodies, `100 Continue`, and
  IPv4/IPv6 host parsing.

Runtime VPN activation still requires a properly signed build and provisioning
profile with the entitlements above.
