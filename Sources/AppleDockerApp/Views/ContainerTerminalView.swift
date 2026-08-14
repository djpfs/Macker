//===----------------------------------------------------------------------===//
// ContainerTerminalView — multi-session integrated terminal for a container.
//
// Each container can have multiple independent shell sessions. Sessions are
// stored in AppState and survive tab switches. New sessions can be added with
// the "+" button and closed with the "×" button on the tab.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// A multi-session integrated terminal for a container.
struct ContainerTerminalView: View {
    @Environment(AppState.self) private var state
    let containerID: String

    /// The currently selected session's stable UUID.
    @State private var selectedSessionID: UUID?

    private var sessions: [ContainerTerminalSession] {
        state.terminalSessions(for: containerID)
    }

    private var selectedSession: ContainerTerminalSession? {
        sessions.first { $0.objectID == selectedSessionID } ?? sessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionTabBar
            Divider()
            if let session = selectedSession {
                SingleTerminalView(session: session)
                    .id(session.objectID)
            } else {
                ProgressView("Connecting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Ensure at least one session exists and select it.
            let existing = state.terminalSessions(for: containerID)
            selectedSessionID = existing[0].objectID
            existing[0].connect()
        }
    }

    // MARK: Session tab bar

    private var sessionTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(sessions, id: \.objectID) { session in
                        sessionTab(session)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider().frame(height: 24)

            // Add new session
            Button {
                let newSession = state.addTerminalSession(for: containerID)
                selectedSessionID = newSession.objectID
                newSession.connect()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("New terminal session")
            .padding(.trailing, 6)
        }
        .background(.bar)
    }

    private func sessionTab(_ session: ContainerTerminalSession) -> some View {
        let isSelected = session.objectID == (selectedSessionID ?? sessions.first?.objectID)
        return HStack(spacing: 4) {
            if session.isConnected {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            Text(session.sessionLabel)
                .font(.caption)
            if sessions.count > 1 {
                Button {
                    state.removeTerminalSession(session)
                    // Select the last remaining session if the removed one was active.
                    if isSelected {
                        selectedSessionID = state.terminalSessions(for: containerID).last?.objectID
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Close session")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSessionID = session.objectID
        }
    }
}

// MARK: - Single terminal panel

/// The terminal output + input UI for one session.
private struct SingleTerminalView: View {
    @Bindable var session: ContainerTerminalSession
    @State private var command = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(session.output.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: session.output.count) {
                    if let last = session.output.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Enter command…", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendCommand() }
                Button("Send") { sendCommand() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isConnected)
                Button("Clear") { session.output.removeAll() }
                    .buttonStyle(.bordered)
                    .help("Clear terminal output")
            }
            .padding(8)
        }
        .onAppear {
            if !session.isConnected {
                session.connect()
            }
        }
    }

    private func sendCommand() {
        let cmd = command
        command = ""
        session.sendCommand(cmd)
    }
}

