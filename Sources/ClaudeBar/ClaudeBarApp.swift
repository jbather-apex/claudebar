import SwiftUI
import ServiceManagement

@main
struct ClaudeBarApp: App {
    @StateObject private var store: SessionStore

    init() {
        let store = SessionStore()
        _store = StateObject(wrappedValue: store)
        Task { @MainActor in store.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            SessionListView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: SessionStore

    // Template PNG rendered from the app logo; falls back to SF Symbols
    // when running without a bundle (`swift run`).
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some View {
        let count = store.attentionCount
        if let logo = Self.logo {
            Image(nsImage: logo)
        } else {
            Image(systemName: store.sessions.isEmpty ? "moon.zzz" : "sparkles")
        }
        if count > 1 {
            Text("\(count)")
            Image(systemName: "exclamationmark")
                .fontWeight(.heavy)
        } else if count == 1 {
            Image(systemName: "exclamationmark")
                .fontWeight(.heavy)
        }
    }
}

struct SessionListView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude Sessions")
                    .font(.headline)
                Spacer()
                Text("\(store.sessions.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if store.sessions.isEmpty {
                Text("No Claude sessions running")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session)
                            if session.id != store.sessions.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }

            Divider()

            HStack(spacing: 12) {
                if !store.hooksInstalled {
                    InstallHooksButton(store: store)
                }
                LaunchAtLoginToggle()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }
}

struct SessionRow: View {
    let session: ClaudeSession

    var body: some View {
        Button {
            if let pid = session.pid {
                TerminalJumper.jump(toPid: pid)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    StatePill(state: session.state)
                }
                HStack(spacing: 6) {
                    Text(session.displayCwd)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let since = session.waitingSince, session.state.needsAttention {
                        (Text("waiting ") + Text(since, style: .relative))
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                if session.state.needsAttention, let message = session.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(session.state == .idle ? 0.6 : 1.0)
    }
}

struct StatePill: View {
    let state: SessionState

    var color: Color {
        switch state {
        case .working: return .blue
        case .needsPermission: return .red
        case .needsInput: return .orange
        case .idle: return .gray
        }
    }

    var body: some View {
        Text(state.displayName)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct InstallHooksButton: View {
    @ObservedObject var store: SessionStore
    @State private var confirming = false

    var body: some View {
        Button("Install hooks…") { confirming = true }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .confirmationDialog(
                "Add ClaudeBar hooks to ~/.claude/settings.json?",
                isPresented: $confirming
            ) {
                Button("Install") { store.installHooks() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing settings are preserved and backed up to settings.json.claudebar-bak. Hooks give instant permission-prompt alerts; they apply to sessions started after installing. Without them, ClaudeBar still lists sessions by polling.")
            }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        if available {
            Toggle("Launch at login", isOn: $enabled)
                .toggleStyle(.checkbox)
                .onChange(of: enabled) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        NSLog("ClaudeBar: launch-at-login failed: \(error)")
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }
}
