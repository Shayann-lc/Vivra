import AppIntents

struct VivraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickLogIntent(),
            phrases: [
                "Quick log in \(.applicationName)",
                "Log in \(.applicationName)",
            ],
            shortTitle: "Quick Log",
            systemImageName: "plus.circle"
        )
    }
}
