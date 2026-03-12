//
//  AppCommands.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

import SwiftUI
import SwiftData

struct AppCommands: Commands {
    let shortcutHandler: KeyboardShortcutHandler

    var body: some Commands {
        CommandMenu("Browser") {
            Button("New Tab") {
                shortcutHandler.openNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                shortcutHandler.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Reopen Closed Tab") {
                shortcutHandler.reopenTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Focus URL Bar") {
                shortcutHandler.focusURLBar()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Refresh Page") {
                shortcutHandler.reloadActiveTab()
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Divider()
            
            Button("Go Back") {
                shortcutHandler.goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            
            Button("Go Forward") {
                shortcutHandler.goForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            
            Divider()
            
            Button("Next Tab") {
                shortcutHandler.nextTab()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            
            Button("Previous Tab") {
                shortcutHandler.previousTab()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            
            Divider()
            
            Button("Toggle Sidebar") {
                shortcutHandler.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: .command)

            Divider()

            Button("Find in Page") {
                shortcutHandler.findInPage()
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Button("Developer Tools") {
                shortcutHandler.openDevTools()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            // Removes 'New Window' and 'New Private Window'
        }
        
        CommandGroup(replacing: .toolbar) {
            // Removes 'Show Tab Bar' and 'Show All Tabs'
            Button("Zoom In") {
                shortcutHandler.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            
            Button("Zoom Out") {
                shortcutHandler.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            
            Button("Actual Size") {
                shortcutHandler.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
        
        CommandGroup(replacing: .sidebar) {
            // Removes 'Show Sidebar' (system version)
        }
    }
}
