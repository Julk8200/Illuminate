//
//  IlluminateApp.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//


import SwiftUI
import SwiftData

@main
struct IlluminateApp: App {
    @StateObject private var tabManager = TabManager.shared
    @StateObject private var viewModel = ContentViewModel(tabManager: TabManager.shared)
    private let keyboardShortcutHandler: KeyboardShortcutHandler
    private let backgroundResourceManager: BackgroundResourceManager
    private let runtimeSecurityMonitor: RuntimeSecurityMonitor
    let modelContainer: ModelContainer
    
    init() {
        let center = NotificationCenter.default
        keyboardShortcutHandler = KeyboardShortcutHandler(notificationCenter: center)
        backgroundResourceManager = BackgroundResourceManager()
        runtimeSecurityMonitor = RuntimeSecurityMonitor(notificationCenter: center)
        do {
            modelContainer = try ModelContainer(for: Bookmark.self, Password.self)
            PasswordService.shared.setContainer(modelContainer)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
        
        runtimeSecurityMonitor.startMonitoring()
        backgroundResourceManager.start()
        configureNotificationLogging(notificationCenter: center)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tabManager)
                .environmentObject(viewModel)
                .frame(minWidth: 600, minHeight: 450)
                .onOpenURL { url in
                    tabManager.createTab(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(modelContainer)
        .defaultSize(width: 1180, height: 720)
        .commands {
            AppCommands(shortcutHandler: keyboardShortcutHandler)
            BookmarksCommands(shortcutHandler: keyboardShortcutHandler, tabManager: tabManager, modelContainer: modelContainer)
        }
    }

    private func configureNotificationLogging(notificationCenter: NotificationCenter) {
        [Notification.Name.newTab, .focusURLBar, .openBookmarks]
            .forEach { name in
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                    AppLog.ui("Received event: \(name.rawValue)")
                }
            }
    }
}
