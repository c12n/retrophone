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

    /* Set by the app when launched with --rp-automation-download-<build>:
     * the import sheet opens and downloads that firmware from Apple,
     * imports it, then creates and opens a machine — the full first-run
     * flow, unattended (the CI download rig uses this). */
    var automationDownload: KnownFirmware?

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
            .sheet(isPresented: $showImporter) {
                ImportView(autoDownload: automationDownload,
                           onImported: handleImported)
            }
            .sheet(isPresented: $showCreate) { CreateMachineView() }
            .onAppear {
                if let machine = automationMachine, path.isEmpty {
                    path = [machine]
                }
                if let download = automationDownload,
                   store.firmware?.build != download.build {
                    showImporter = true
                } else if automationDownload != nil {
                    handleImported()
                }
            }
        }
    }

    /* After an automation-download import: open the existing machine,
     * or create a CPU-software one and open it — what a user would do. */
    private func handleImported() {
        guard automationDownload != nil else { return }
        if let machine = store.machines.first {
            if path.isEmpty { path = [machine] }
        } else if let firmware = store.firmware,
                  let machine = store.createMachine(
                    name: "iOS \(firmware.version) CPU software",
                    softwareRender: true) {
            path = [machine]
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
    @StateObject private var downloader = FirmwareDownloader()
    @State private var didAutoStart = false

    /* The CI download rig passes a firmware to fetch as soon as the
     * sheet appears; a normal open leaves this nil. */
    var autoDownload: KnownFirmware?
    var onImported: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pick a version to download it straight from " +
                         "Apple's servers — it is verified and imported " +
                         "automatically. Or choose an IPSW file you " +
                         "already have.")
                        .foregroundStyle(.secondary)
                }
                Section("Download from Apple") {
                    ForEach(KnownFirmware.all) { firmware in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(firmware.displayName) " +
                                     "(\(firmware.build))")
                                Text("\(firmware.sizeText) · Apple servers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Download") {
                                downloader.start(firmware)
                            }
                            .buttonStyle(.bordered)
                            .disabled(downloader.isBusy || working != nil)
                        }
                    }
                    downloadStatus
                }
                Section("From a file") {
                    Button("Choose IPSW file…") { picking = true }
                        .disabled(working != nil || downloader.isBusy)
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
            .onAppear {
                if let autoDownload, !didAutoStart {
                    didAutoStart = true
                    downloader.start(autoDownload)
                }
            }
            .onChange(of: downloader.phase) { _, newPhase in
                if case .ready(let url) = newPhase, working == nil {
                    importIPSW(url)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if let active = downloader.active {
            switch downloader.phase {
            case .downloading(let fraction, let written, let total):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction)
                    HStack {
                        Text("\(active.displayName): " +
                             ByteCountFormatter.string(
                                fromByteCount: written, countStyle: .file) +
                             " of " +
                             ByteCountFormatter.string(
                                fromByteCount: total, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .destructive) {
                            downloader.cancel()
                        }
                        .font(.caption)
                    }
                }
            case .verifying:
                HStack {
                    ProgressView()
                    Text("Verifying \(active.displayName) download…")
                }
            case .failed(let failure):
                Text(failure).foregroundStyle(.red)
            default:
                EmptyView()
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
            let result = RPImport.importIPSW(atPath: url.path,
                intoDirectory: firmwareDir.path, error: &error)
            DispatchQueue.main.async {
                working = nil
                if let result {
                    store.recordFirmware(FirmwareMeta(
                        version: result.productVersion, build: result.build))
                    /* A downloaded IPSW has served its purpose once the
                     * firmware set is extracted — don't keep 300+ MB. */
                    if url.path.contains("FirmwareDownloads") {
                        try? FileManager.default.removeItem(at: url)
                    }
                    onImported?()
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
