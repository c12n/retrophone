//
//  RetroPhone — FirmwareDownload.swift
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
//  One-tap firmware downloads straight from Apple's own servers
//  (secure-appldnld.apple.com — the same hosts iTunes/Finder restore
//  from). The two supported iPhone1,2 IPSWs are pinned with their
//  SHA-256 digests and sizes; a download is hashed before it is handed
//  to the importer, so a corrupt or substituted file never reaches
//  the extraction step (which verifies the firmware contents again).
//
import Foundation
import CryptoKit

struct KnownFirmware: Identifiable {
    var id: String { build }
    let displayName: String
    let version: String
    let build: String
    let url: URL
    let sha256: String
    let fileSize: Int64

    var fileName: String { url.lastPathComponent }
    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    static let all: [KnownFirmware] = [
        KnownFirmware(
            displayName: "iPhone OS 3.1.3", version: "3.1.3", build: "7E18",
            url: URL(string: "https://secure-appldnld.apple.com/iPhone/" +
                     "061-7468.20100202.pbnrt/" +
                     "iPhone1,2_3.1.3_7E18_Restore.ipsw")!,
            sha256: "31eb8734ddf0a86d21a850e437028b902f2f085c81ccf3dd39471f1596438cf3",
            fileSize: 239_139_281),
        KnownFirmware(
            displayName: "iOS 4.2.1", version: "4.2.1", build: "8C148",
            url: URL(string: "https://secure-appldnld.apple.com/iPhone4/" +
                     "061-9853.20101122.Vfgt5/" +
                     "iPhone1,2_4.2.1_8C148_Restore.ipsw")!,
            sha256: "98e5969c3baed660c9a26e94cd7ed4b3cdb7175900f448bcc2223bf885835ce0",
            fileSize: 338_579_762),
    ]

    static func named(build: String) -> KnownFirmware? {
        all.first { $0.build == build }
    }
}

/* Downloads one IPSW with progress, then verifies its SHA-256. The
 * finished file lands in Caches/FirmwareDownloads; the caller imports
 * it and deletes it (the extracted firmware set is what the app keeps). */
final class FirmwareDownloader: NSObject, ObservableObject,
                                URLSessionDownloadDelegate {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double, written: Int64, total: Int64)
        case verifying
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var active: KnownFirmware?

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    func start(_ firmware: KnownFirmware) {
        session?.invalidateAndCancel()
        active = firmware
        phase = .downloading(fraction: 0, written: 0, total: firmware.fileSize)
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config,
                                 delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: firmware.url)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
    }

    /* ------------------------------------------------ URLSessionDownloadDelegate */

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite : (active?.fileSize ?? 0)
        let fraction = total > 0
            ? Double(totalBytesWritten) / Double(total) : 0
        DispatchQueue.main.async {
            self.phase = .downloading(fraction: fraction,
                                      written: totalBytesWritten,
                                      total: total)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let firmware = active else { return }
        if let http = downloadTask.response as? HTTPURLResponse,
           http.statusCode != 200 {
            DispatchQueue.main.async {
                self.phase = .failed(
                    "Apple's server returned HTTP \(http.statusCode).")
            }
            return
        }
        /* The temp file only lives for this callback — move it first. */
        let fileManager = FileManager.default
        let dir = fileManager.urls(for: .cachesDirectory,
                                   in: .userDomainMask)[0]
            .appendingPathComponent("FirmwareDownloads", isDirectory: true)
        try? fileManager.createDirectory(at: dir,
                                         withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(firmware.fileName)
        try? fileManager.removeItem(at: dest)
        do {
            try fileManager.moveItem(at: location, to: dest)
        } catch {
            DispatchQueue.main.async {
                self.phase = .failed("Couldn't save the download: " +
                                     error.localizedDescription)
            }
            return
        }
        DispatchQueue.main.async { self.phase = .verifying }
        DispatchQueue.global(qos: .userInitiated).async {
            let digest = Self.sha256(of: dest)
            DispatchQueue.main.async {
                if digest == firmware.sha256 {
                    self.phase = .ready(dest)
                } else {
                    try? fileManager.removeItem(at: dest)
                    self.phase = .failed(
                        "The downloaded file failed its integrity check " +
                        "and was deleted. Please try again.")
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        DispatchQueue.main.async {
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorCancelled {
                self.phase = .idle
                self.active = nil
            } else if case .downloading = self.phase {
                self.phase = .failed("Download failed: " +
                                     error.localizedDescription)
            }
        }
    }

    /* Streaming SHA-256 (the IPSW is far too big to load into memory). */
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
