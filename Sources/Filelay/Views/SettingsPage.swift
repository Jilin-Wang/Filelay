import SwiftUI

struct SettingsPage: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        Form {
            Section(L10n.text(.about, language)) {
                HStack {
                    Text(L10n.text(.version, language))
                    Spacer()
                    Text(BuildInfo.version).foregroundStyle(.secondary)
                }
                HStack {
                    Text(L10n.text(.build, language))
                    Spacer()
                    Text(BuildInfo.build).foregroundStyle(.secondary)
                }
            }

            Section(L10n.text(.managedRoot, language)) {
                Text(store.settings.managedRootPath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section(L10n.text(.syncBehavior, language)) {
                Picker(L10n.text(.syncInterval, language), selection: Binding(
                    get: { store.settings.syncIntervalSeconds },
                    set: { store.updateSyncInterval($0) }
                )) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .pickerStyle(.segmented)
                .hoverCursor(.pointingHand)

                Toggle(L10n.text(.autoHints, language), isOn: Binding(
                    get: { store.settings.associationHintsEnabled },
                    set: { store.updateAssociationHintsEnabled($0) }
                ))
                .hoverCursor(.pointingHand)

                Toggle(L10n.text(.launchAtLogin, language), isOn: Binding(
                    get: { store.settings.launchAtLoginEnabled },
                    set: { store.updateLaunchAtLoginEnabled($0) }
                ))
                .hoverCursor(.pointingHand)

                Picker(L10n.text(.language, language), selection: Binding(
                    get: { store.settings.language },
                    set: { store.updateLanguage($0) }
                )) {
                    Text("简体中文").tag(AppLanguage.zhHans)
                    Text("English").tag(AppLanguage.en)
                }
                .hoverCursor(.pointingHand)
            }

            Section(L10n.text(.devices, language)) {
                ForEach(store.knownDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text(device.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.id == store.currentDevice.id {
                            Text(L10n.text(.currentMachine, language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppChromeColor.windowBackground)
        .padding()
    }
}
