// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import AppKit
import PDFKit
import ImageCaptureCore
import Quartz

@MainActor struct PDFScannerRequest: Identifiable { let id = UUID(); let russian: Bool; let create: ([URL]) -> String? }

// Only this session's private directory is removed; scanner-supplied external URLs are never deleted.
final class PDFScanStorage {
    let folder: URL
    init(parent: URL = FileManager.default.temporaryDirectory) {
        folder = parent.appendingPathComponent("BotPlusScan-"+UUID().uuidString,isDirectory: true)
    }
    func prepare() throws { try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true) }
    func cleanup() throws {
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
    deinit { try? cleanup() }
}
@MainActor final class PDFScannerModel: NSObject, ObservableObject, @preconcurrency ICDeviceBrowserDelegate {
    let browser = ICDeviceBrowser()
    let storage = PDFScanStorage()
    var folder: URL { storage.folder }
    private var active = false
    @Published var devices: [ICScannerDevice] = []
    @Published var selected = 0
    @Published var files: [URL] = []
    @Published var error: String?
    func start() {
        guard !active else { return }
        do { try storage.prepare() } catch { self.error = error.localizedDescription; return }
        active = true
        browser.delegate = self
        let mask = ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.local.rawValue
        let selection: ICDeviceTypeMask? = ICDeviceTypeMask(rawValue: mask)
        browser.browsedDeviceTypeMask = selection ?? .scanner
        browser.start()
    }
    func stop() {
        active = false
        for device in devices { device.cancelScan() }
        browser.stop(); browser.delegate = nil
        devices.removeAll(); files.removeAll()
        do { try storage.cleanup() } catch { self.error = error.localizedDescription }
    }
    func receive(_ url: URL?,error: String?) {
        guard active else { try? storage.cleanup(); return }
        if let error { self.error = error }
        if let url,!files.contains(url) { files.append(url) }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser,didAdd device: ICDevice,moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        DispatchQueue.main.async { [weak self] in if let self,self.active,!self.devices.contains(where: { $0 === scanner }) { self.devices.append(scanner) } }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser,didRemove device: ICDevice,moreGoing: Bool) {
        DispatchQueue.main.async { [weak self] in self?.devices.removeAll { $0 === device }; self?.selected = 0 }
    }
}
struct PDFScannerPanel: View {
    let request: PDFScannerRequest
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PDFScannerModel()
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(request.russian ? "PDF со сканера" : "PDF from scanner").font(.title2)
            if model.devices.isEmpty { Text(request.russian ? "Подключите совместимый сканер Image Capture и установите его драйвер." : "Connect an Image Capture compatible scanner and install its driver.") }
            else {
                Picker(request.russian ? "Сканер" : "Scanner",selection: $model.selected) { ForEach(Array(model.devices.enumerated()),id: \.offset) { index,device in Text(device.name ?? "Scanner").tag(index) } }
                if model.devices.indices.contains(model.selected) { NativeScannerView(device: model.devices[model.selected],folder: model.folder) { url,error in
                    model.receive(url,error: error)
                }.frame(height: 500) }
            }
            Text("\(request.russian ? "Получено файлов" : "Scanned files"): \(model.files.count)")
            if let error = model.error { Text(error).foregroundStyle(.orange) }
            Text(request.russian ? "Временные сканы удаляются при закрытии. Созданный PDF остаётся открытым для сохранения." : "Temporary scans are removed on close. The created PDF stays open for saving.").font(.caption)
            HStack { Spacer(); Button(request.russian ? "Закрыть" : "Close") { dismiss() }; Button(request.russian ? "Создать PDF" : "Create PDF") {
                model.error = request.create(model.files)
                if model.error == nil { dismiss() }
            }.disabled(model.files.isEmpty) }
        }.padding(24).frame(width: 880,height: 650).onAppear { model.start() }.onDisappear { model.stop() }
    }
}
struct NativeScannerView: NSViewRepresentable {
    let device: ICScannerDevice, folder: URL
    let receive: (URL?,String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(receive: receive) }
    func makeNSView(context: Context) -> IKScannerDeviceView {
        let view = IKScannerDeviceView(); view.delegate = context.coordinator; view.scannerDevice = device; view.mode = .advanced; view.transferMode = .fileBased
        view.downloadsDirectory = folder; view.documentName = "Scan"; view.displaysDownloadsDirectoryControl = false; view.displaysPostProcessApplicationControl = false
        return view
    }
    func updateNSView(_ view: IKScannerDeviceView,context: Context) { if view.scannerDevice !== device { view.scannerDevice = device }; context.coordinator.receive = receive }
    static func dismantleNSView(_ view: IKScannerDeviceView,coordinator: Coordinator) { view.scannerDevice = nil; view.delegate = nil }
    @MainActor final class Coordinator: NSObject, IKScannerDeviceViewDelegate {
        var receive: (URL?,String?) -> Void
        init(receive: @escaping (URL?,String?) -> Void) { self.receive = receive }
        nonisolated func scannerDeviceView(_ view: IKScannerDeviceView!,didScanTo url: URL!,fileData data: Data!,error: (any Error)!) {
            let message = error?.localizedDescription
            DispatchQueue.main.async { [weak self] in self?.receive(url,message) }
        }
        nonisolated func scannerDeviceView(_ view: IKScannerDeviceView!,didEncounterError error: (any Error)!) {
            let message = error?.localizedDescription
            DispatchQueue.main.async { [weak self] in self?.receive(nil,message) }
        }
    }
}
