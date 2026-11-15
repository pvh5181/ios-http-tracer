//
//  PacketTunnelProvider.swift
//  HTTPTraceTunnel
//

import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
  private var proxy: HTTPProxyServer?

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    do {
      try BackgroundCapturePaths.ensureDirectory()
    } catch {
      completionHandler(error)
      return
    }

    let proxy = HTTPProxyServer()
    self.proxy = proxy

    proxy.start { [weak self] result in
      guard let self else {
        completionHandler(ProxyError.upstream("The tunnel provider was released while starting."))
        return
      }

      switch result {
      case .failure(let error):
        self.proxy = nil
        completionHandler(error)

      case .success(let port):
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")
        settings.mtu = 1_500

        // Keep the tunnel active for the system-wide proxy settings, but
        // do not route ordinary IP traffic into a packet stack. HTTP and
        // HTTPS clients connect to the loopback proxy directly.
        let ipv4 = NEIPv4Settings(
          addresses: ["198.18.0.1"],
          subnetMasks: ["255.255.255.255"]
        )
        ipv4.includedRoutes = []
        settings.ipv4Settings = ipv4

        let proxySettings = NEProxySettings()
        let server = NEProxyServer(address: "127.0.0.1", port: Int(port))
        proxySettings.httpEnabled = true
        proxySettings.httpServer = server
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = server
        proxySettings.excludeSimpleHostnames = false
        proxySettings.exceptionList = []
        settings.proxySettings = proxySettings

        self.setTunnelNetworkSettings(settings) { error in
          if let error {
            proxy.stop()
            self.proxy = nil
            completionHandler(error)
          } else {
            completionHandler(nil)
          }
        }
      }
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    proxy?.stop()
    proxy = nil
    completionHandler()
  }
}
