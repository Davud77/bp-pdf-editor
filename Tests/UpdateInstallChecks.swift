// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import AppKit

@main
struct UpdateInstallChecks {
    @MainActor static func main() throws {
        let previousPreference = UserDefaults.standard.object(forKey: "BotPlus.update.previousApp")
        defer { if let previousPreference { UserDefaults.standard.set(previousPreference,forKey: "BotPlus.update.previousApp") } else { UserDefaults.standard.removeObject(forKey: "BotPlus.update.previousApp") } }
        let version = CommandLine.arguments[4]
        let archive = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2],isDirectory: true)
        let entitlements = CommandLine.arguments[3]
        let unpacked = root.appendingPathComponent("unpacked",isDirectory: true)
        let expected = unpacked.appendingPathComponent("BotPlus PDF Editor.app")
        let staged = try UpdateInstaller.unpack(archive: archive,directory: unpacked,version: version,current: expected)
        let current = root.appendingPathComponent("BotPlus PDF Editor.app")
        try FileManager.default.copyItem(at: staged,to: current)
        let info = current.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info),format: nil) as! [String:Any]
        plist["CFBundleShortVersionString"] = "1.6"
        try PropertyListSerialization.data(fromPropertyList: plist,format: .xml,options: 0).write(to: info)
        let signer = Process(); signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); signer.arguments = ["--force","--sign","-","--entitlements",entitlements,current.path]
        try signer.run(); signer.waitUntilExit()
        guard signer.terminationStatus == 0 else { fatalError("fixture signature failed") }
        do { try UpdateInstaller.validate(app: staged,version: "9.9",current: current); fatalError("wrong version accepted") } catch { }
        try UpdateInstaller.install(staged: staged,current: current,folder: root,version: version)
        guard try UpdateInstaller.bundleVersion(current) == version else { fatalError("updated bundle not installed") }
        let backups = try FileManager.default.contentsOfDirectory(at: root,includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("BotPlus PDF Editor.previous-") }
        guard backups.count == 1 else { fatalError("previous bundle not retained") }
        do { try UpdateInstaller.install(staged: staged,current: current,folder: root,version: version); fatalError("same version accepted") } catch { }
        try Data("damaged".utf8).write(to: current.appendingPathComponent("Contents/Resources/injected.txt"))
        do { try UpdateInstaller.validate(app: current,version: version,current: staged); fatalError("invalid signature accepted") } catch { }
        print("PASS: packaged universal ZIP, code signature, bundle ID/version, filesystem install, retained backup, downgrade/same-version and tamper rejection")
    }
}
