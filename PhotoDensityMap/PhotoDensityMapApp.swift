//
//  PhotoDensityMapApp.swift
//  PhotoDensityMap
//
//  Created with Claude
//

import SwiftUI

@main
struct PhotoDensityMapApp: App {
    @StateObject private var photoManager = PhotoLocationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(photoManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("View") {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Divider()
                
                Button("Reset View") {
                    NotificationCenter.default.post(name: .resetView, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let resetView = Notification.Name("resetView")
}
