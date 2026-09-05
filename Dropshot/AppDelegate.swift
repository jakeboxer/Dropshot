//
//  AppDelegate.swift
//  Dropshot
//
//  Created by Jake Card on 9/3/26.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var dropZone: DropZonePanelController!
    private var dropCoordinator: DropCoordinator!
    private var dragObserver: AppKitDragObserver!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: "Dropshot"
        )

        dropZone = DropZonePanelController(
            onAcceptedDrop: { [weak self] _ in
                self?.dropCoordinator.endDestinationInteraction()
            },
            onRejectedDrop: { [weak self] in
                self?.dropCoordinator.endDestinationInteraction()
            }
        )
        dropZone.anchor(to: statusItem.button)
        dropCoordinator = DropCoordinator(presentation: dropZone)
        dragObserver = AppKitDragObserver { [weak self] descriptor in
            self?.dropCoordinator.observeDrag(descriptor)
        }
        dragObserver.start()
        
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Dropshot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragObserver?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
