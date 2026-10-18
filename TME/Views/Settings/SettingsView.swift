import SwiftData
import SwiftUI
import TMECore
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [LedgerEntry]
    @State private var editingBalance = false
    @AppStorage(TagActivities.enabledKey) private var askInDynamicIsland = true
    @AppStorage(TagNotifications.announceFiledKey) private var announceAutoFiled = true
    private var balance = BalanceReader()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { editingBalance = true } label: {
                        HStack {
                            Label {
                                Text("Starting balance")
                            } icon: {
                                Image(systemName: "indianrupeesign.circle")
                            }
                            Spacer()
                            Text(balanceSummary)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }
                } footer: {
                    if balance.starting != nil {
                        Text("Your balance is this amount, plus income and minus spending logged since.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        SMSSetupView()
                    } label: {
                        Label("Auto-log bank SMS", systemImage: "message.badge")
                    }
                    NavigationLink {
                        SMSTesterView()
                    } label: {
                        Label("Test a bank SMS", systemImage: "text.magnifyingglass")
                    }
                    NavigationLink {
                        FloatingButtonSetupView()
                    } label: {
                        Label("Floating quick-add button", systemImage: "circle.circle")
                    }
                } header: {
                    Text("Automation")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NotificationStatusRow()
                    Toggle(isOn: $askInDynamicIsland) {
                        Label {
                            Text("Ask in the Dynamic Island")
                        } icon: {
                            Image(systemName: "capsule.portrait")
                        }
                    }
                    Toggle(isOn: $announceAutoFiled) {
                        Label {
                            Text("Tell me about automatic filing")
                        } icon: {
                            Image(systemName: "checkmark.bubble")
                        }
                    }
                    NavigationLink {
                        PromptHistoryView()
                    } label: {
                        Label("Prompt history", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("Category prompts")
                } footer: {
                    Text("New payments pop up at the top of the screen with category buttons; when iOS doesn't allow that, you get a notification. Payments from merchants TME already knows are filed for you, with a quiet notification.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    ShareLink(
                        item: CSVFile(text: CSVExport.csv(for: entries)),
                        preview: SharePreview("TME export")
                    ) {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything stays on this iPhone. It's included in your normal iPhone backups.")
                }
                .listRowBackground(Theme.surface)
            }
            .matteList()
            .toggleStyle(SwitchToggleStyle(tint: Theme.income))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDone")
                }
            }
            .sheet(isPresented: $editingBalance) {
                StartingBalanceEditor()
            }
        }
    }

    private var balanceSummary: String {
        guard let starting = balance.starting else { return "Not set" }
        return "\(Rupees.format(paise: starting.paise)) on \(starting.asOf.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

private struct NotificationStatusRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        HStack {
            Label(statusText, systemImage: status == .authorized ? "bell.badge" : "bell.slash")
            Spacer()
            switch status {
            case .notDetermined:
                Button("Turn on") {
                    Task {
                        await TagNotifications.requestPermissionIfNeeded()
                        await refresh()
                    }
                }
            case .denied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            default:
                EmptyView()
            }
        }
        .task(id: scenePhase) { await refresh() }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Category prompts are on"
        case .denied: "Category prompts are off"
        default: "Category prompts not set up"
        }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

/// What TME did with each payment the SMS automation sent it, newest first.
struct PromptHistoryView: View {
    @State private var events: [PromptLog.Event] = []

    var body: some View {
        List {
            ForEach(events.reversed()) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.text)
                        .font(.callout)
                    Text(event.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .overlay {
            if events.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "clock",
                    description: Text("Each payment your SMS automation sends to TME shows up here, with what TME did about it.")
                )
            }
        }
        .matteList()
        .navigationTitle("Prompt history")
        .toolbar {
            if !events.isEmpty {
                Button("Clear") {
                    PromptLog.clear()
                    events = []
                }
            }
        }
        .task { events = PromptLog.load() }
        .refreshable { events = PromptLog.load() }
    }
}
