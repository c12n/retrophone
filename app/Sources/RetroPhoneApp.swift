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

    /* The download rig launches with --rp-automation-download-8C148 (or
     * -7E18): the app downloads that firmware from Apple, imports it,
     * then creates and opens a machine — the full first-run flow. */
    private var automationDownload: KnownFirmware? {
        for argument in ProcessInfo.processInfo.arguments {
            let prefix = "--rp-automation-download-"
            if argument.hasPrefix(prefix) {
                return KnownFirmware.named(
                    build: String(argument.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            ContentView(automationMachine: automationMachine,
                        automationDownload: automationDownload)
                .environmentObject(store)
        }
    }
}
