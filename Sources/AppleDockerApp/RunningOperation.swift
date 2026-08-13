//===----------------------------------------------------------------------===//
// RunningOperation — a background operation being tracked by the app.
//
// Operations are registered in AppState so the sidebar can show a green dot
// on the section that owns them and the toolbar can surface a live list of
// everything running in the background.
//===----------------------------------------------------------------------===//

import Foundation

/// A single in-flight background operation.
struct RunningOperation: Identifiable, Equatable {
    let id: UUID
    /// Human-readable description, e.g. "Up myapp" or "Pull nginx:latest".
    let title: String
    /// The sidebar section that owns this operation (used for the green dot).
    let section: SidebarItem?
    /// When the operation started.
    let startedAt: Date
}
