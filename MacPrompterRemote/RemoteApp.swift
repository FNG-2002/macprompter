import SwiftUI

@main
struct RemoteApp: App {
    @State private var client = RemoteClient(store: KeychainPairedMacStore())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(client: client)
                .onAppear { client.deviceName = UIDevice.current.name }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // No background networking: the link only lives while the app is visible.
                    if phase == .active { client.startBrowsing() } else if phase == .background { client.suspend() }
                }
                .onChange(of: client.isConnected) { _, connected in
                    UIApplication.shared.isIdleTimerDisabled = connected
                }
                #if DEBUG
                // Manual end-to-end runs only (docs/REMOTE.md): `-RemoteDebugPairCode 123456`
                // pairs with the first Mac that shows a code.
                .onChange(of: client.discovered) { _, macs in
                    guard let code = UserDefaults.standard.string(forKey: "RemoteDebugPairCode"), client.phase == .idle,
                          let mac = macs.first(where: { $0.pairingSalt != nil && client.pairing(for: $0) == nil }) else { return }
                    Task { await client.pair(mac, code: code) }
                }
                #endif
        }
    }
}

/// Pairing keys stay in this device's keychain and are never synced to iCloud.
@MainActor
final class KeychainPairedMacStore: PairedMacStoring {
    private let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.fng-2002.macprompter.remote.pairings",
        kSecAttrAccount as String: "paired-macs",
    ]

    func load() -> [PairedMac] {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([PairedMac].self, from: data)) ?? []
    }

    func save(_ macs: [PairedMac]) {
        SecItemDelete(base as CFDictionary)
        guard !macs.isEmpty, let data = try? JSONEncoder().encode(macs) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
