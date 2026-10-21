//===----------------------------------------------------------------------===//
// AppTheme — user-selected appearance, persisted via @AppStorage("appTheme").
//
// The theme is applied in two channels that must agree:
//   • SwiftUI: `colorScheme` in the environment, resolved here. Every view
//     that reads it (text, ThemedBackground, …) redraws when it changes.
//   • AppKit: NSApp / NSWindow / hosting view appearance, for the title bar,
//     toolbar, sidebar vibrancy and standard controls.
//
// `.preferredColorScheme` is not used. It does not redraw custom fills when
// the choice changes, and it does not reset the AppKit appearance.
//===----------------------------------------------------------------------===//

import SwiftUI
import AppKit

/// Appearance choice in Settings. `system` follows macOS, the other two force a scheme.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The scheme views should render with. `system` uses the scheme macOS reports.
    func resolved(system: ColorScheme) -> ColorScheme {
        switch self {
        case .system: system
        case .light: .light
        case .dark: .dark
        }
    }

    /// AppKit appearance for window chrome. `nil` means follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Sets the AppKit appearance on the app and on every open window, including
    /// its hosting view. `nil` clears it, so System really goes back to the system.
    @MainActor
    func applyToWindows() {
        NSApp.appearance = nsAppearance
        for window in NSApp.windows {
            window.appearance = nsAppearance
            window.contentView?.appearance = nsAppearance
        }
    }
}

extension View {
    /// Applies the saved theme to this view tree and to the windows it lives in.
    func appThemed() -> some View {
        modifier(AppThemeModifier())
    }
}

private struct AppThemeModifier: ViewModifier {
    @AppStorage("appTheme") private var appTheme = AppTheme.system
    /// Read above the override below, so it always reflects macOS.
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, appTheme.resolved(system: systemScheme))
            .onChange(of: appTheme, initial: true) { _, theme in
                theme.applyToWindows()
            }
    }
}
