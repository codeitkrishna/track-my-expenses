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
            PanelPage {
                PanelSection(footer: balance.starting != nil ? Text("Your balance is this amount, plus income and minus spending logged since.") : nil) {
                    Button { editingBalance = true } label: {
                        PanelRow("Starting balance", symbol: "indianrupeesign.circle") {
                            Text(balanceSummary)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(RowPressStyle())
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        PanelRow("Categories", symbol: "square.grid.2x2") { RowChevron() }
                    }
                    .buttonStyle(RowPressStyle())
                }

                PanelSection("Automation") {
                    NavigationLink {
                        SMSSetupView()
                    } label: {
                        PanelRow("Auto-log bank SMS", symbol: "message.badge") { RowChevron() }
                    }
                    .buttonStyle(RowPressStyle())
                    NavigationLink {
                        SMSTesterView()
                    } label: {
                        PanelRow("Test a bank SMS", symbol: "text.magnifyingglass") { RowChevron() }
                    }
                    .buttonStyle(RowPressStyle())
                    NavigationLink {
                        FloatingButtonSetupView()
                    } label: {
                        PanelRow("Floating quick-add button", symbol: "circle.circle") { RowChevron() }
                    }
                    .buttonStyle(RowPressStyle())
                }

                PanelSection(
                    "Category prompts",
                    footer: Text("New payments pop up at the top of the screen with category buttons; when iOS doesn't allow that, you get a notification. Payments from merchants TME already knows are filed for you, with a quiet notification.")
                ) {
                    NotificationStatusRow()
                    PanelRow("Ask in the Dynamic Island", symbol: "capsule.portrait") {
                        InstrumentSwitch(isOn: $askInDynamicIsland)
                            .accessibilityLabel("Ask in the Dynamic Island")
                    }
                    PanelRow("Tell me about automatic filing", symbol: "checkmark.bubble") {
                        InstrumentSwitch(isOn: $announceAutoFiled)
                            .accessibilityLabel("Tell me about automatic filing")
                    }
                    NavigationLink {
                        PromptHistoryView()
                    } label: {
                        PanelRow("Prompt history", symbol: "clock.arrow.circlepath") { RowChevron() }
                    }
                    .buttonStyle(RowPressStyle())
                }

                PanelSection("Your data", footer: Text("Everything stays on this iPhone. It's included in your normal iPhone backups.")) {
                    ShareLink(
                        item: CSVFile(text: CSVExport.csv(for: entries)),
                        preview: SharePreview("TME export")
                    ) {
                        PanelRow("Export as CSV", symbol: "square.and.arrow.up") { RowChevron() }
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
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
        PanelRow(statusText, symbol: status == .authorized ? "bell.badge" : "bell.slash") {
            switch status {
            case .notDetermined:
                Button("Turn on") {
                    Task {
                        await TagNotifications.requestPermissionIfNeeded()
                        await refresh()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.income)
            case .denied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.income)
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
        PanelPage {
            if events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Nothing yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Each payment your SMS automation sends to TME shows up here, with what TME did about it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                PanelSection {
                    ForEach(events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.text)
                                .font(.callout)
                                .foregroundStyle(.white)
                            Text(event.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
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
    }
}
