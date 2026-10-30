//
//  RetroPhone — ContentView.swift
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showImporter = false
    @State private var showCreate = false
    @State private var path: [Machine] = []

    /* Set by the app when launched with --rp-automation-open-first-machine:
     * the first machine opens and boots unattended (the CI simulator rig
     * uses this; it mirrors what a user tap does, nothing more). */
    var automationMachine: Machine?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Firmware") {
                    HStack {
                        Image(systemName: store.firmware == nil
                              ? "exclamationmark.triangle" : "checkmark.circle")
                        Text(store.firmwareURLDescription)
                        Spacer()
                        Button(store.firmware == nil ? "Import" : "Replace") {
                            showImporter = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section("Machines") {
                    if store.machines.isEmpty {
                        Text("No machines yet. Import an iPhone1,2 IPSW " +
                             "(iPhone OS 3.1.3 or iOS 4.2.1), then create one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.machines) { machine in
                        NavigationLink(value: machine) {
                            VStack(alignment: .leading) {
                                Text(machine.name)
                                Text(machine.softwareRender
                                     ? "iOS \(machine.build) · CPU software graphics"
                                     : "iOS \(machine.build) · MBX graphics")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { store.deleteMachine(store.machines[index]) }
                    }
                    if store.firmware != nil {
                        Button("New machine") { showCreate = true }
                    }
                }
            }
            .navigationTitle("RetroPhone")
            .navigationDestination(for: Machine.self) { machine in
                EmulatorScreen(machine: machine)
            }
            .sheet(isPresented: $showImporter) { ImportView() }
            .sheet(isPresented: $showCreate) { CreateMachineView() }
            .onAppear {
                if let machine = automationMachine, path.isEmpty {
                    path = [machine]
                }
            }
        }
    }
}

/* ------------------------------------------------------------- importing */

struct ImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var picking = false
    @State private var working: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose an iPhone1,2 Restore IPSW — iPhone OS " +
                         "3.1.3 (7E18) or iOS 4.2.1 (8C148). The three " +
                         "files the emulator boots are extracted and " +
                         "verified against known-good digests.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Choose IPSW file…") { picking = true }
                        .disabled(working != nil)
                    if let working {
                        HStack { ProgressView(); Text(working) }
                    }
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import firmware")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.zip, .data]) { result in
                if case .success(let url) = result { importIPSW(url) }
            }
        }
    }

    private func importIPSW(_ url: URL) {
        working = "Importing (this takes a minute)…"
        message = nil
        let firmwareDir = store.firmwareDir
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var error: NSString?
            let result = RPImport.importIPSWAtPath(
                url.path, intoDirectory: firmwareDir.path, error: &error)
            DispatchQueue.main.async {
                working = nil
                if let result {
                    store.recordFirmware(FirmwareMeta(
                        version: result.productVersion, build: result.build))
                    dismiss()
                } else {
                    message = (error as String?) ?? "Import failed."
                }
            }
        }
    }
}

/* -------------------------------------------------------- creating machines */

struct CreateMachineView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var name = "iPhone"
    @State private var softwareRender = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Graphics", selection: $softwareRender) {
                    Text("CPU software (compatibility)").tag(true)
                    Text("MBX (experimental)").tag(false)
                }
                Text("CPU software renders with the guest's own software " +
                     "compositor. MBX presents the emulated PowerVR GPU, " +
                     "which is experimental and known to stall iOS 4.2.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("New machine")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.createMachine(name: name.isEmpty ? "iPhone" : name,
                                            softwareRender: softwareRender)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
