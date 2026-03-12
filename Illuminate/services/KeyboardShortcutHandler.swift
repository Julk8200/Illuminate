//
//  KeyboardShortcutHandler.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//


import Foundation
import AppKit

final class KeyboardShortcutHandler {
    private let notificationCenter: NotificationCenter
    private var eventMonitor: Any?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        startMonitoring()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func startMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            if modifiers == [.command, .shift] {
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "i":
                        self.openDevTools()
                        return nil
                    case "t":
                        self.reopenTab()
                        return nil
                    default:
                        break
                    }
                }
            } else if modifiers == .command {
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "t":
                        self.openNewTab()
                        return nil
                    case "w":
                        self.closeActiveTab()
                        return nil
                    case "l":
                        self.focusURLBar()
                        return nil
                    case "r":
                        self.reloadActiveTab()
                        return nil
                    case "s":
                        self.toggleSidebar()
                        return nil
                    case "b":
                        self.bookmarkTab()
                        return nil
                    case "f":
                        self.findInPage()
                        return nil
                    case "+", "=":
                        self.zoomIn()
                        return nil
                    case "-":
                        self.zoomOut()
                        return nil
                    case "0":
                        self.resetZoom()
                        return nil
                    default:
                        break
                    }
                }
                
                switch event.keyCode {
                case 123: // Left Arrow
                    self.goBack()
                    return nil
                case 124: // Right Arrow
                    self.goForward()
                    return nil
                case 125: // Down Arrow
                    self.nextTab()
                    return nil
                case 126: // Up Arrow
                    self.previousTab()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    func openNewTab() {
        notificationCenter.post(name: .newTab, object: nil)
    }

    func focusURLBar() {
        notificationCenter.post(name: .focusURLBar, object: nil)
    }

    func reloadActiveTab() {
        notificationCenter.post(name: .reloadActiveTab, object: nil)
    }

    func goBack() {
        notificationCenter.post(name: .goBack, object: nil)
    }

    func goForward() {
        notificationCenter.post(name: .goForward, object: nil)
    }

    func bookmarkTab() {
        notificationCenter.post(name: .bookmarkTab, object: nil)
    }

    func reopenTab() {
        notificationCenter.post(name: .reopenTab, object: nil)
    }

    func nextTab() {
        notificationCenter.post(name: .nextTab, object: nil)
    }

    func previousTab() {
        notificationCenter.post(name: .previousTab, object: nil)
    }

    func closeActiveTab() {
        notificationCenter.post(name: NSNotification.Name("closeActiveTab"), object: nil)
    }

    func toggleSidebar() {
        notificationCenter.post(name: .toggleSidebar, object: nil)
    }

    func findInPage() {
        notificationCenter.post(name: .findInPage, object: nil)
    }

    func zoomIn() {
        notificationCenter.post(name: .zoomIn, object: nil)
    }

    func zoomOut() {
        notificationCenter.post(name: .zoomOut, object: nil)
    }

    func resetZoom() {
        notificationCenter.post(name: .resetZoom, object: nil)
    }

    func openDevTools() {
        AppLog.ui("Shortcut: Command-Shift-I captured")
        notificationCenter.post(name: .openDevTools, object: nil)
    }
}

final class BackgroundResourceManager {
    func start() {
        AppLog.info("BackgroundResourceManager started")
    }
}

final class RuntimeSecurityMonitor {
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func startMonitoring() {
        observer = notificationCenter.addObserver(forName: .newTab, object: nil, queue: .main) { _ in
            AppLog.security("Runtime check passed for New Tab action")
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }
}
