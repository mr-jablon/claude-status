import ClaudeStatusCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Bindable var monitor: UsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { model.showingSettings = false } label: { Label("Zpět", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text("Nastavení").font(.headline)
            }

            Stepper("5h limit: upozornit při \(Int(monitor.settings.sessionWarn)) %",
                    value: $monitor.settings.sessionWarn, in: 50...95, step: 5)
            Stepper("Den: upozornit při \(Int(monitor.settings.dayWarn)) %",
                    value: $monitor.settings.dayWarn, in: 50...95, step: 5)
            Stepper("Týden: napřed o víc než \(Int(monitor.settings.weeklyPaceMargin)) p. b.",
                    value: $monitor.settings.weeklyPaceMargin, in: 5...30, step: 5)
            Stepper("Předpověď dne: \(Int(monitor.settings.dayForecastHorizonMinutes)) min dopředu",
                    value: $monitor.settings.dayForecastHorizonMinutes, in: 15...180, step: 15)

            Divider()
            Text("Oznámení").font(.subheadline.weight(.medium))
            ForEach(NotificationKind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: enabledBinding(kind))
            }
            Button("Poslat zkušební oznámení") { model.sendTestNotification() }

            Divider()
            Toggle("Spouštět po přihlášení", isOn: Binding(
                get: { monitor.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if let message = model.loginItemMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func enabledBinding(_ kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { monitor.settings.enabled.contains(kind) },
            set: { isOn in
                if isOn { monitor.settings.enabled.insert(kind) } else { monitor.settings.enabled.remove(kind) }
            }
        )
    }
}
