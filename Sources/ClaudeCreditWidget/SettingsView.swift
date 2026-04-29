import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CreditStore

    @State private var sessionKey: String = ""
    @State private var orgId: String = ""
    @State private var intervalMinutes: Double = 5
    @State private var hasExistingKey: Bool = false
    @State private var importMessage: String?
    @State private var importMessageIsError: Bool = false
    @State private var savedFlash: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings").font(.headline)

                if let signInDate = store.lastSignInAt {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in active — monitoring session")
                                .font(.callout)
                            Text("Last signed in \(signInDate.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.10))
                    .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.lastSignInAt == nil ? "Quick setup" : "Refresh session")
                        .font(.caption).foregroundColor(.secondary)
                    Button {
                        Task { await runImport() }
                    } label: {
                        HStack {
                            Image(systemName: store.lastSignInAt == nil
                                  ? "arrow.down.circle.fill"
                                  : "arrow.clockwise.circle.fill")
                            Text(store.isImporting
                                 ? "Importing…"
                                 : (store.lastSignInAt == nil
                                    ? "Sign in with Chrome"
                                    : "Refresh session from Chrome"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(store.isImporting)
                    Text("Reads your platform.claude.com session from Chrome. macOS may prompt once for Keychain access.")
                        .font(.caption2).foregroundColor(.secondary)
                    if let msg = importMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(importMessageIsError ? .orange : .green)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual setup").font(.caption).foregroundColor(.secondary)
                    TextField("Organization ID", text: $orgId)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Session Key").font(.caption).foregroundColor(.secondary)
                        if hasExistingKey {
                            Text("(stored — leave blank to keep)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    SecureField("sk-ant-sid02-…", text: $sessionKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Refresh interval").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(intervalMinutes)) min").font(.caption.monospacedDigit())
                    }
                    Slider(value: $intervalMinutes, in: 1...30, step: 1)
                }

                HStack {
                    if savedFlash {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Saved").font(.caption).foregroundColor(.green)
                        }
                        .transition(.opacity)
                    }
                    Spacer()
                    Button("Close") { closeWindow() }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .onAppear { loadValues() }
    }

    private func loadValues() {
        orgId = store.orgId
        intervalMinutes = max(1, Double(store.refreshIntervalSeconds) / 60)
        hasExistingKey = (KeychainStore.load(key: "sessionKey")?.isEmpty == false)
    }

    private func save() {
        if !sessionKey.isEmpty {
            KeychainStore.save(key: "sessionKey", value: sessionKey)
            sessionKey = ""
            hasExistingKey = true
        }
        store.orgId = orgId
        store.refreshIntervalSeconds = Int(intervalMinutes * 60)
        store.scheduleTimer()
        Task { await store.refresh() }

        withAnimation(.easeIn(duration: 0.15)) { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.4)) { savedFlash = false }
        }
    }

    private func runImport() async {
        importMessage = nil
        let result = await store.signInWithChrome()
        switch result {
        case .success:
            importMessage = "Sign in active, monitoring session."
            importMessageIsError = false
            loadValues()
        case .failure(let err):
            importMessage = err.localizedDescription
            importMessageIsError = true
        }
    }

    private func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}
