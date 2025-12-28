//
//  SemanticImageSearchApp.swift
//  SemanticImageSearch
//
//  A macOS application for semantic image search using local vector models.
//

import SwiftUI

@main
struct SemanticImageSearchApp: App {
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Folder...") {
                    appState.showFolderPicker = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
