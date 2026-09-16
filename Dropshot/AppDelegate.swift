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
        do {
            try DroppedInput.cleanupAbandonedInputs()
        } catch {
            NSLog("Dropshot could not clean abandoned Ephemeral Inputs.")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: "Dropshot"
        )

        dropZone = DropZonePanelController(
            onDestinationEntered: { [weak self] optionHeld in
                self?.dropCoordinator.destinationEntered(optionHeld: optionHeld)
            },
            onDestinationUpdated: { [weak self] optionHeld in
                self?.dropCoordinator.destinationUpdated(optionHeld: optionHeld)
            },
            onDestinationExited: { [weak self] in
                self?.dropCoordinator.destinationExited()
            },
            onCancelled: { [weak self] in
                self?.dropCoordinator.cancelInteraction()
            },
            onAcceptedDrop: { [weak self] _ in
                self?.dropCoordinator.endDestinationInteraction()
            },
            onRejectedDrop: { [weak self] in
                self?.dropCoordinator.cancelInteraction()
            }
        )
        dropZone.anchor(to: statusItem.button)
        dropCoordinator = DropCoordinator(presentation: dropZone)
        dragObserver = AppKitDragObserver(
            onObservation: { [weak self] descriptor in
                self?.dropCoordinator.observeDrag(descriptor)
            },
            onPointerStateChanged: { [weak self] pointerState in
                self?.dropCoordinator.pointerStateChanged(pointerState)
            },
            onMouseReleased: { [weak self] in
                self?.dropCoordinator.mouseReleased()
            },
            onInterrupted: { [weak self] in
                self?.dropCoordinator.interruptInteraction()
            }
        )
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
