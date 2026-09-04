//
//  main.swift
//  Dropshot
//
//  Created by Jake Card on 9/3/26.
//

import Cocoa

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
