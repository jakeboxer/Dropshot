//
//  AppDelegate.swift
//  Dropshot
//
//  Created by Jake Card on 9/3/26.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: "Dropshot"
        )
        
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Dropshot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

