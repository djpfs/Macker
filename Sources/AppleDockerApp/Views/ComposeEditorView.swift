//===----------------------------------------------------------------------===//
// ComposeEditorView — integrated text editor for docker-compose.yml and
// Dockerfile files, with project templates for quick scaffolding.
//===----------------------------------------------------------------------===//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Project templates

/// A pre-built project template the user can load as a starting point.
struct ProjectTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let systemImage: String
    let compose: String
    let dockerfile: String?
}

extension ProjectTemplate {
    static let all: [ProjectTemplate] = [
        .nodeApp,
        .pythonFlask,
        .goApp,
        .postgresOnly,
        .webNginx,
    ]

    // MARK: Node.js + Postgres

    static let nodeApp = ProjectTemplate(
        name: "Node.js + PostgreSQL",
        description: "Express API backed by a PostgreSQL database.",
        systemImage: "server.rack",
        compose: """
version: "3.9"
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://user:password@db:5432/appdb
    depends_on:
      - db
  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=appdb
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
""",
        dockerfile: """
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
"""
    )

    // MARK: Python / Flask + Redis

    static let pythonFlask = ProjectTemplate(
        name: "Python Flask + Redis",
        description: "Flask web app with a Redis cache.",
        systemImage: "flame",
        compose: """
version: "3.9"
services:
  web:
    build: .
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=development
      - REDIS_URL=redis://cache:6379
    depends_on:
      - cache
  cache:
    image: redis:7-alpine
volumes: {}
""",
        dockerfile: """
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["flask", "run", "--host=0.0.0.0"]
"""
    )

    // MARK: Go service

    static let goApp = ProjectTemplate(
        name: "Go Service",
        description: "Minimal Go HTTP service with multi-stage build.",
        systemImage: "bolt",
        compose: """
version: "3.9"
services:
  api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
""",
        dockerfile: """
# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app ./cmd/server

# Runtime stage
FROM alpine:3.20
COPY --from=builder /app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
"""
    )

    // MARK: PostgreSQL only

    static let postgresOnly = ProjectTemplate(
        name: "PostgreSQL",
        description: "Stand-alone PostgreSQL instance for local development.",
        systemImage: "cylinder",
        compose: """
version: "3.9"
services:
  db:
    image: postgres:16
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=dev
      - POSTGRES_PASSWORD=devpassword
      - POSTGRES_DB=devdb
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
""",
        dockerfile: nil
    )

    // MARK: Nginx static site

    static let webNginx = ProjectTemplate(
        name: "Nginx Static Site",
        description: "Nginx serving a static site from ./html.",
        systemImage: "globe",
        compose: """
version: "3.9"
services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
""",
        dockerfile: nil
    )
}

// MARK: - Editor view

/// Full-screen editor for a docker-compose.yml or Dockerfile, with project
/// template picker and file save/open capabilities.
struct ComposeEditorView: View {
    /// The file currently being edited ("compose" or "dockerfile").
    enum FileKind: String, CaseIterable, Identifiable {
        case compose = "docker-compose.yml"
        case dockerfile = "Dockerfile"
        var id: String { rawValue }
    }

    @State private var selectedKind: FileKind = .compose
    @State private var composeText: String = ""
    @State private var dockerfileText: String = ""
    @State private var showTemplatePicker = false
    @State private var saveMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            editorArea
        }
        .navigationTitle("Editor")
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePicker(composeText: $composeText, dockerfileText: $dockerfileText)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("File", selection: $selectedKind) {
                ForEach(FileKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer()

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button {
                showTemplatePicker = true
            } label: {
                Label("Templates", systemImage: "square.on.square")
            }
            .buttonStyle(.bordered)
            .help("Choose a project template")

            Button {
                openFile()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .help("Open a file to edit")

            Button {
                saveFile()
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .help("Save the current file")
        }
        .padding(12)
    }

    // MARK: Editor area

    @ViewBuilder
    private var editorArea: some View {
        let text = selectedKind == .compose ? $composeText : $dockerfileText
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                if currentText.isEmpty {
                    Text(selectedKind == .compose
                         ? "Paste or type your docker-compose.yml here…"
                         : "Paste or type your Dockerfile here…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
    }

    private var currentText: String {
        selectedKind == .compose ? composeText : dockerfileText
    }

    // MARK: File I/O

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.yaml, .plainText, .item]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent.lowercased()
            if name.contains("dockerfile") {
                dockerfileText = content
                selectedKind = .dockerfile
            } else {
                composeText = content
                selectedKind = .compose
            }
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = selectedKind.rawValue
        panel.allowedContentTypes = [.yaml, .plainText, .item]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = selectedKind == .compose ? composeText : dockerfileText
            try text.write(to: url, atomically: true, encoding: .utf8)
            saveMessage = "Saved to \(url.lastPathComponent)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                saveMessage = nil
            }
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Template picker sheet

private struct TemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var composeText: String
    @Binding var dockerfileText: String
    @State private var selected: ProjectTemplate?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project Templates")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(16)
            Divider()

            HStack(spacing: 0) {
                // Template list
                List(ProjectTemplate.all, selection: $selected) { template in
                    templateRow(template)
                        .tag(template as ProjectTemplate?)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 200, maxWidth: 240)

                Divider()

                // Preview
                if let tpl = selected {
                    templatePreview(tpl)
                } else {
                    Text("Select a template to preview")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Use Template") {
                    if let tpl = selected {
                        composeText = tpl.compose
                        dockerfileText = tpl.dockerfile ?? ""
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 440)
    }

    private func templateRow(_ template: ProjectTemplate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: template.systemImage)
                .frame(width: 20)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.body.weight(.medium))
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func templatePreview(_ template: ProjectTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("docker-compose.yml")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(template.compose)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if let df = template.dockerfile {
                    Text("Dockerfile")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(df)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
