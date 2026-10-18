import SwiftData
import SwiftUI
import TMECore
import UserNotifications

struct SettingsView: View {
    @Query private var entries: [LedgerEntry]
    @State private var editingBalance = false
    @AppStorage(TagActivities.enabledKey) private var askInDynamicIsland = true
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
                                    .foregroundStyle(.tint)
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

                Section {
                    NotificationStatusRow()
                    Toggle(isOn: $askInDynamicIsland) {
                        Label {
                            Text("Ask in the Dynamic Island")
                        } icon: {
                            Image(systemName: "capsule.portrait")
                                .foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text("Category prompts")
                } footer: {
                    Text("New payments pop up at the top of the screen with category buttons. When iOS doesn't allow that, you get a notification instead.")
                }

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
            }
            .navigationTitle("Settings")
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
