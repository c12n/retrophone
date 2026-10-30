//
//  RetroPhone — RetroPhoneApp.swift
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
import SwiftUI

@main
struct RetroPhoneApp: App {
    @StateObject private var store = Store()

    /* The simulator rig launches with --rp-automation-open-first-machine:
     * open the first machine and boot it, exactly as a tap would. */
    private var automationMachine: Machine? {
        guard ProcessInfo.processInfo.arguments
            .contains("--rp-automation-open-first-machine") else { return nil }
        return store.machines.first
    }

    var body: some Scene {
        WindowGroup {
            ContentView(automationMachine: automationMachine)
                .environmentObject(store)
        }
    }
}
