//===----------------------------------------------------------------------===//
// ContainerTerminalView — an integrated terminal for a running container.
//
// Uses a persistent ContainerTerminalSession from AppState so the shell and
// its output survive tab switches. The Send button enables once the session is
// connected; commands are written to the shell's stdin and echoed locally.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// A simple integrated terminal for a container.
struct ContainerTerminalView: View {
    @Environment(AppState.self) private var state
    let containerID: String
    @State private var command = ""
    @State private var session: ContainerTerminalSession?

    var body: some View {
        Group {
            if let session {
                terminalContent(session)
            } else {
                ProgressView("Connecting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            let s = state.terminalSession(for: containerID)
            session = s
            s.connect()
        }
    }

    private func terminalContent(_ session: ContainerTerminalSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terminal")
                    .font(.headline)
                Spacer()
                if session.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)

            Divider()

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
                    .onSubmit { sendCommand(session) }
                Button("Send") { sendCommand(session) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isConnected)
            }
            .padding(8)
        }
    }

    private func sendCommand(_ session: ContainerTerminalSession) {
        let cmd = command
        command = ""
        session.sendCommand(cmd)
    }
}
