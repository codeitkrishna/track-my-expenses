import PhotosUI
import SwiftData
import SwiftUI
import TMECore

/// Scan a shop's UPI code, then pay it with any UPI app on the phone. The
/// payment is logged when you come back (see `ScanPay`).
struct ScanPayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var payee: UPIPayee?

    var body: some View {
        NavigationStack {
            ZStack {
                if let payee {
                    UPIPayScreen(payee: payee, scanAgain: { withAnimation(.snappy) { self.payee = nil } }, handedOver: { dismiss() })
                        .transition(.opacity)
                } else {
                    QRScanScreen { found in withAnimation(.snappy) { payee = found } }
                        .transition(.opacity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("scanClose")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(Theme.canvas)
    }
}

// MARK: - Scanning

/// The camera behind a dimmed screen with a clear square to aim with, and
/// a way to read the code from a picture instead.
private struct QRScanScreen: View {
    let found: (UPIPayee) -> Void
    @State private var camera = QRCamera()
    /// Says why the last code didn't work, for a moment.
    @State private var notice: String?
    @State private var rejected: Set<String> = []
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var done = false

    var body: some View {
        // One full-screen space for every layer, so the clear square, the
        // corners and the message line up whatever the bars and notch take.
        GeometryReader { proxy in
            let side = min(proxy.size.width - 80, 280)
            let window = CGRect(x: (proxy.size.width - side) / 2, y: max(proxy.size.height * 0.42 - side / 2, proxy.safeAreaInsets.top + 70), width: side, height: side)
            ZStack(alignment: .topLeading) {
                if camera.state == .running {
                    CameraPreview(session: camera.session)
                        .accessibilityHidden(true)
                }
                // Everything but the square is dimmed.
                Rectangle()
                    .fill(.black.opacity(camera.state == .running ? 0.55 : 1))
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .frame(width: window.width, height: window.height)
                            .position(x: window.midX, y: window.midY)
                    }
                    .accessibilityHidden(true)
                ViewfinderCorners()
                    .stroke(done ? Theme.income : .white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
                    .animation(.snappy(duration: 0.2), value: done)
                    .accessibilityHidden(true)
                if camera.state == .denied || camera.state == .unavailable {
                    NoCamera(denied: camera.state == .denied)
                        .frame(width: window.width - 32)
                        .position(x: window.midX, y: window.midY)
                }
                VStack(spacing: 18) {
                    Text(notice ?? "Point at a UPI QR code")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(notice == nil ? .white : Theme.expense)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(.snappy, value: notice)
                        .accessibilityIdentifier("scanCaption")
                    // The picker's label is built off the main actor.
                    let photoTitle = reading ? "Reading…" : "From photo"
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(photoTitle, systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 48)
                        }
                        .buttonStyle(.glass)
                        .disabled(reading)
                        .accessibilityIdentifier("scanPhoto")
                        if camera.hasTorch, camera.state == .running {
                            Button { camera.toggleTorch() } label: {
                                Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(camera.torchOn ? .black : .white)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(camera.torchOn ? .white : .clear)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel(camera.torchOn ? "Turn off the torch" : "Turn on the torch")
                            .accessibilityIdentifier("scanTorch")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: min(window.maxY + 90, proxy.size.height - proxy.safeAreaInsets.bottom - 50))
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: done)
        .sensoryFeedback(.warning, trigger: notice) { _, new in new != nil }
        .task {
            camera.onCode = { handle($0) }
            await camera.start()
        }
        #if DEBUG
        .task {
            // Tests and screenshots: read this as if the camera had.
            guard let encoded = LaunchOptions.value(after: "-scanCode"),
                  let data = Data(base64Encoded: encoded), let code = String(data: data, encoding: .utf8)
            else { return }
            try? await Task.sleep(for: .milliseconds(400))
            handle(code)
        }
        #endif
        .task(id: notice) {
            guard notice != nil else { return }
            // Long enough to read: the camera won't say it again for the same code.
            try? await Task.sleep(for: .seconds(4))
            notice = nil
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .onDisappear { camera.stop() }
    }

    private func handle(_ code: String) {
        guard !done else { return }
        if let payee = UPIQR.parse(code) {
            done = true
            camera.stop()
            Task {
                // A beat for the corners to turn green.
                try? await Task.sleep(for: .milliseconds(250))
                found(payee)
            }
        } else if !rejected.contains(code) {
            // The camera reads a code many times a second; say so once.
            rejected.insert(code)
            notice = "That isn't a UPI payment code."
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        reading = true
        defer {
            reading = false
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            notice = "Couldn't open that picture."
            return
        }
        let codes = await QRImage.codes(in: data)
        if let code = codes.first(where: { UPIQR.parse($0) != nil }) {
            handle(code)
        } else {
            notice = codes.isEmpty ? "No QR code in that picture." : "That isn't a UPI payment code."
        }
    }
}

/// Four rounded corners of a square, like the marks in a camera's viewfinder.
private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.16
        let radius: CGFloat = 28
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0), (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * (radius + arm)))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: corner.x + dx * radius, y: corner.y), control: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * (radius + arm), y: corner.y))
        }
        return path
    }
}

/// In place of the camera, when there isn't one or TME may not use it.
private struct NoCamera: View {
    let denied: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: denied ? "video.slash" : "camera")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(denied ? "TME can't use the camera" : "No camera here")
                .font(.headline)
                .foregroundStyle(.white)
            Text(denied ? "Allow it in Settings, or read the code from a photo." : "Read the code from a photo instead.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(settings) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("scanOpenSettings")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("noCamera")
    }
}

private extension View {
    /// Cuts `mask` out of this view.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay { mask().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}

// MARK: - Paying

/// Who the code pays, and the UPI apps on this phone to pay them with.
private struct UPIPayScreen: View {
    let payee: UPIPayee
    let scanAgain: () -> Void
    let handedOver: () -> Void
    @Environment(\.modelContext) private var context
    @State private var apps: [UPIApp] = []
    @State private var copied = 0
    @State private var opening: String?
    @State private var failed: String?
    /// Goes to the payment app as the remark, and onto the logged payment.
    @State private var note: String
    @FocusState private var writingNote: Bool

    init(payee: UPIPayee, scanAgain: @escaping () -> Void, handedOver: @escaping () -> Void) {
        self.payee = payee
        self.scanAgain = scanAgain
        self.handedOver = handedOver
        _note = State(initialValue: payee.note ?? "")
    }

    var body: some View {
        let known = Tagging.rememberedCategory(for: payee.displayName, flow: .expense, in: context)
        PanelPage {
            VStack(spacing: 10) {
                if let known {
                    CategoryIcon(category: known, size: 64)
                } else {
                    Text(payee.displayName.prefix(1).uppercased())
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Theme.surfaceRaised, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(payee.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 4)
                    .accessibilityIdentifier("payeeName")
                Button {
                    UIPasteboard.general.string = payee.address
                    copied += 1
                } label: {
                    HStack(spacing: 6) {
                        Text(payee.address)
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: copied > 0 ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("UPI ID \(payee.address)")
                .accessibilityHint("Copies it")
                .accessibilityIdentifier("payeeUPI")
                if let amount = payee.amountPaise {
                    VStack(spacing: 2) {
                        HeroAmount(paise: amount, size: 44)
                        MonoLabel("Amount set by the shop")
                    }
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("payeeAmount")
                }
                if let known {
                    Text("Filed under \(known.name) last time")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                noteField
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            if apps.isEmpty {
                PanelSection(footer: Text("Install PhonePe, Google Pay, Paytm, CRED or BHIM to pay from here, or copy the UPI ID above into any UPI app.")) {
                    PanelRow("No UPI app on this iPhone", symbol: "exclamationmark.circle", tint: Theme.textSecondary)
                        .accessibilityIdentifier("noUPIApps")
                }
            } else {
                PanelSection("Pay with", footer: Text(footer)) {
                    ForEach(apps) { app in
                        Button {
                            writingNote = false
                            Task { await pay(with: app) }
                        } label: {
                            HStack(spacing: 12) {
                                AppMark(app: app)
                                Text(app.name)
                                    .foregroundStyle(.white)
                                Spacer(minLength: 8)
                                if opening == app.id {
                                    ProgressView().tint(.white)
                                } else {
                                    RowChevron()
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .disabled(opening != nil)
                        .accessibilityLabel("Pay with \(app.name)")
                        .accessibilityIdentifier("payWith-\(app.id)")
                    }
                }
            }
            if let failed {
                Text(failed)
                    .font(.footnote)
                    .foregroundStyle(Theme.expense)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                    .accessibilityIdentifier("payFailed")
            }
            Button(action: scanAgain) {
                Label("Scan another code", systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 18)
            .accessibilityIdentifier("scanAgain")
        }
        .sensoryFeedback(.success, trigger: copied)
        .onAppear { apps = ScanPay.installedApps() }
    }

    private var footer: String {
        let opens = payee.amountPaise == nil ? "It opens on the amount screen for this UPI ID." : "It opens ready to pay this amount."
        let remark = note.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " Your note goes with it."
        return opens + remark + " When you've paid, come back to TME and it's logged here."
    }

    /// One note, typed once: the payment app shows it as the remark and TME
    /// keeps it on the payment. Starts as the code's own note, if any.
    private var noteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
            TextField("Note, for you and the shop", text: $note)
                .focused($writingNote)
                .submitLabel(.done)
                .onSubmit { writingNote = false }
                .textInputAutocapitalization(.sentences)
                .font(.subheadline)
                .foregroundStyle(.white)
                .accessibilityIdentifier("payNoteField")
            if !note.isEmpty {
                Button {
                    note = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the note")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .frame(maxWidth: 300)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(writingNote ? .white.opacity(0.35) : Theme.hairline, lineWidth: 1))
        .animation(.snappy(duration: 0.2), value: writingNote)
    }

    private func pay(with app: UPIApp) async {
        failed = nil
        opening = app.id
        let opened = await ScanPay.pay(payee, with: app, note: note)
        opening = nil
        if opened {
            handedOver()
        } else {
            failed = "\(app.name) didn't open. Try another app."
        }
    }
}

/// A UPI app's mark: its initials on its colour.
private struct AppMark: View {
    let app: UPIApp

    var body: some View {
        Group {
            if app.monogram.isEmpty {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
            } else {
                Text(app.monogram)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Color(hex: app.colour), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
