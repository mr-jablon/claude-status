import AppKit
import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Only an installed copy may register: a build inside the repo lives on an encrypted
    /// volume that may not be mounted yet at login.
    static var isInstalledLocation: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix(NSHomeDirectory() + "/Applications/") || path.hasPrefix("/Applications/")
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum WakeObserver {
    static func observe(_ handler: @escaping @MainActor @Sendable () -> Void) {
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
