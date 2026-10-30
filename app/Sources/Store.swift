//
//  RetroPhone — Store.swift
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
//  RetroPhone's own on-disk layout, all inside the app's Documents folder:
//
//    Firmware/                 the one imported firmware set
//      kernel.macho, devicetree.bin, rootfs.img, import-policy-v1
//      meta.json               { version, build }
//    Machines/<id>/
//      machine.json            { id, name, build, softwareRender, createdAt }
//      rootfs-work.img         the machine's writable disk (engine-made)
//
import Foundation

struct FirmwareMeta: Codable {
    var version: String
    var build: String
}

struct Machine: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var build: String
    var softwareRender: Bool
    var createdAt: Date
}

final class Store: ObservableObject {
    @Published private(set) var firmware: FirmwareMeta?
    @Published private(set) var machines: [Machine] = []

    let documents: URL
    var firmwareDir: URL { documents.appendingPathComponent("Firmware") }
    var machinesDir: URL { documents.appendingPathComponent("Machines") }

    init() {
        documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(
            at: machinesDir, withIntermediateDirectories: true)
        reload()
    }

    func machineDir(_ id: String) -> URL {
        machinesDir.appendingPathComponent(id)
    }

    func reload() {
        if let data = try? Data(contentsOf:
                firmwareDir.appendingPathComponent("meta.json")),
           let meta = try? JSONDecoder().decode(FirmwareMeta.self, from: data) {
            firmware = meta
        } else {
            firmware = nil
        }
        var found: [Machine] = []
        if let ids = try? FileManager.default.contentsOfDirectory(
            atPath: machinesDir.path) {
            for id in ids {
                let url = machineDir(id).appendingPathComponent("machine.json")
                if let data = try? Data(contentsOf: url),
                   let m = try? JSONDecoder().decode(Machine.self, from: data) {
                    found.append(m)
                }
            }
        }
        machines = found.sorted { $0.createdAt < $1.createdAt }
    }

    func recordFirmware(_ meta: FirmwareMeta) {
        try? FileManager.default.createDirectory(
            at: firmwareDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: firmwareDir.appendingPathComponent("meta.json"))
        }
        firmware = meta
    }

    @discardableResult
    func createMachine(name: String, softwareRender: Bool) -> Machine? {
        guard let fw = firmware else { return nil }
        let id = String(format: "%08x%08x",
                        UInt32.random(in: 0...UInt32.max),
                        UInt32.random(in: 0...UInt32.max))
        let machine = Machine(id: id, name: name, build: fw.build,
                              softwareRender: softwareRender, createdAt: Date())
        let dir = machineDir(id)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(machine) {
            try? data.write(to: dir.appendingPathComponent("machine.json"))
        }
        machines.append(machine)
        return machine
    }

    func deleteMachine(_ machine: Machine) {
        try? FileManager.default.removeItem(at: machineDir(machine.id))
        machines.removeAll { $0.id == machine.id }
    }

    var firmwareURLDescription: String {
        guard let fw = firmware else { return "No firmware imported" }
        return "iOS \(fw.version) (\(fw.build))"
    }
}
