//
//  RetroPhone — EmulatorModel.swift
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
//  Bridges RPEmulator to SwiftUI: owns the boot lifecycle (provision, then
//  start), polls the guest frame and console on a timer, and publishes the
//  display diagnostics that make the guest's behaviour observable.
//
import SwiftUI

final class EmulatorModel: ObservableObject {
    @Published var frame: UIImage?
    @Published var status: String = "Stopped"
    @Published var detail: String = ""
    @Published var consoleText: String = ""
    @Published var diagnostics: String = ""
    @Published var busy: String? /* non-nil while provisioning */

    private let emulator: RPEmulator
    private let machine: Machine
    private var timer: Timer?
    private var lastRetired: UInt64 = 0
    private var lastPoll = Date()

    init(store: Store, machine: Machine) {
        self.machine = machine
        self.emulator = RPEmulator(
            firmwareDirectory: store.firmwareDir.path,
            machineDirectory: store.machineDir(machine.id).path,
            softwareRender: machine.softwareRender)
    }

    func start() {
        guard timer == nil else { return }
        busy = "Preparing the disk…"
        let emulator = self.emulator
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSString?
            let ok = emulator.provisionWithError(&error)
            DispatchQueue.main.async {
                self.busy = nil
                guard ok else {
                    self.status = "Failed"
                    self.detail = (error as String?) ?? "Provisioning failed."
                    return
                }
                var startError: NSString?
                if emulator.startWithError(&startError) {
                    self.beginPolling()
                } else {
                    self.status = "Failed"
                    self.detail = (startError as String?) ?? "Boot failed."
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        emulator.stop()
        status = emulator.statusText
    }

    private func beginPolling() {
        lastPoll = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0,
                                     repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        if let image = emulator.copyFrameImage() {
            frame = UIImage(cgImage: image)
        }
        let fresh = emulator.drainConsole()
        if !fresh.isEmpty {
            consoleText += fresh
            if consoleText.count > 200_000 {
                consoleText = String(consoleText.suffix(100_000))
            }
        }
        let now = Date()
        let retired = emulator.retiredInstructions
        let elapsed = now.timeIntervalSince(lastPoll)
        let mips = elapsed > 0
            ? Double(retired &- lastRetired) / elapsed / 1_000_000.0 : 0
        lastRetired = retired
        lastPoll = now

        status = emulator.statusText
        detail = emulator.detailText
        let window = emulator.activeWindow
        diagnostics = String(
            format: "%@ · %.1f M insn/s · %.0f fps · %llu frame changes · " +
                    "CLCD %@ · window %@ · fb 0x%08x (%ux%u)",
            emulator.running ? "running" : "stopped",
            mips, emulator.framesPerSecond, emulator.frameChanges,
            emulator.clcdRunning ? "on" : "off",
            window == UInt32.max ? "none" : String(window),
            emulator.framebufferAddress,
            emulator.frameWidth, emulator.frameHeight)
    }

    /* -------------------------------------------------------------- input */

    func touch(phase: String, at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let panelW = emulator.frameWidth > 0 ? Double(emulator.frameWidth) : 320
        let panelH = emulator.frameHeight > 0 ? Double(emulator.frameHeight) : 480
        let x = UInt16(max(0, min(panelW - 1, point.x / size.width * panelW)))
        let y = UInt16(max(0, min(panelH - 1, point.y / size.height * panelH)))
        emulator.sendTouchPhase(phase, x: x, y: y)
    }

    func home(down: Bool) { emulator.setHomeButtonPressed(down) }
    func power(down: Bool) { emulator.setPowerButtonPressed(down) }
}
