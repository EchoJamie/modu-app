import AppKit
import Combine
import Foundation

enum CommandLineToolInstallerError: LocalizedError, Equatable {
    case bundledToolMissing
    case temporaryApplicationLocation
    case targetExists
    case targetIsDirectory
    case installationChanged
    case authorizationCancelled
    case privilegedOperation(String)

    var errorDescription: String? {
        switch self {
        case .bundledToolMissing:
            L10n.string(.settingsCLIMissingTool)
        case .temporaryApplicationLocation:
            L10n.string(.settingsCLITemporaryApp)
        case .targetExists:
            L10n.string(.settingsCLITargetExists)
        case .targetIsDirectory:
            L10n.string(.settingsCLITargetDirectory)
        case .installationChanged:
            L10n.string(.settingsCLIInstallationChanged)
        case .authorizationCancelled:
            L10n.string(.settingsCLIAuthorizationCancelled)
        case .privilegedOperation(let message):
            message
        }
    }
}

enum CommandLineToolOperation: Equatable {
    case install(sourceURL: URL, targetURL: URL, replacingExisting: Bool)
    case uninstall(sourceURL: URL, targetURL: URL)
}

@MainActor
final class CommandLineToolInstaller: ObservableObject {
    nonisolated static let systemInstallationURL = URL(
        fileURLWithPath: "/usr/local/bin/modu"
    )

    @Published private(set) var installedURL: URL?
    @Published private(set) var errorMessage: String?

    private let fileManager: FileManager
    private let bundledToolURL: URL
    private let applicationURL: URL
    private let installationURL: URL
    private let performPrivilegedOperation: (CommandLineToolOperation) throws -> Void

    init(
        fileManager: FileManager = .default,
        applicationURL: URL = Bundle.main.bundleURL,
        bundledToolURL: URL? = nil,
        installationURL: URL = CommandLineToolInstaller.systemInstallationURL,
        performPrivilegedOperation: ((CommandLineToolOperation) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.applicationURL = applicationURL.standardizedFileURL
        self.bundledToolURL = (
            bundledToolURL
                ?? applicationURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("CLI", isDirectory: true)
                    .appendingPathComponent("modu")
        ).standardizedFileURL
        self.installationURL = installationURL.standardizedFileURL
        self.performPrivilegedOperation = performPrivilegedOperation
            ?? Self.executeWithAdministratorPrivileges
        refreshInstallationStatus()
    }

    var isInstalled: Bool { installedURL != nil }

    func installFromSettings() {
        errorMessage = nil
        do {
            try install()
        } catch CommandLineToolInstallerError.targetExists {
            guard confirmReplacement() else { return }
            do {
                try install(replacingExisting: true)
            } catch CommandLineToolInstallerError.authorizationCancelled {
                return
            } catch {
                report(error)
            }
        } catch CommandLineToolInstallerError.authorizationCancelled {
            return
        } catch {
            report(error)
        }
    }

    func uninstallFromSettings() {
        errorMessage = nil
        do {
            try uninstall()
        } catch CommandLineToolInstallerError.authorizationCancelled {
            return
        } catch {
            report(error)
        }
    }

    func install(replacingExisting: Bool = false) throws {
        guard isStableApplicationLocation else {
            throw CommandLineToolInstallerError.temporaryApplicationLocation
        }
        guard fileManager.isExecutableFile(atPath: bundledToolURL.path) else {
            throw CommandLineToolInstallerError.bundledToolMissing
        }

        if isCurrentInstallation {
            installedURL = installationURL
            return
        }

        if itemExistsIncludingSymbolicLink(at: installationURL) {
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(
                atPath: installationURL.path,
                isDirectory: &isDirectory
            )
            if !isSymbolicLink(at: installationURL), isDirectory.boolValue {
                throw CommandLineToolInstallerError.targetIsDirectory
            }
            guard replacingExisting else {
                throw CommandLineToolInstallerError.targetExists
            }
        }

        try performPrivilegedOperation(
            .install(
                sourceURL: bundledToolURL,
                targetURL: installationURL,
                replacingExisting: replacingExisting
            )
        )
        guard isCurrentInstallation else {
            throw CommandLineToolInstallerError.installationChanged
        }
        installedURL = installationURL
        errorMessage = nil
    }

    func uninstall() throws {
        guard isCurrentInstallation else {
            refreshInstallationStatus()
            throw CommandLineToolInstallerError.installationChanged
        }
        try performPrivilegedOperation(
            .uninstall(sourceURL: bundledToolURL, targetURL: installationURL)
        )
        guard !itemExistsIncludingSymbolicLink(at: installationURL) else {
            throw CommandLineToolInstallerError.installationChanged
        }
        installedURL = nil
        errorMessage = nil
    }

    func refreshInstallationStatus() {
        installedURL = isCurrentInstallation ? installationURL : nil
    }

    private var isStableApplicationLocation: Bool {
        let path = applicationURL.resolvingSymlinksInPath().path
        return !path.hasPrefix("/Volumes/") && !path.contains("/AppTranslocation/")
    }

    private var isCurrentInstallation: Bool {
        guard
            let destination = try? fileManager.destinationOfSymbolicLink(
                atPath: installationURL.path
            )
        else {
            return false
        }
        let destinationURL = URL(
            fileURLWithPath: destination,
            relativeTo: installationURL.deletingLastPathComponent()
        ).resolvingSymlinksInPath().standardizedFileURL
        return destinationURL == bundledToolURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func itemExistsIncludingSymbolicLink(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) || isSymbolicLink(at: url)
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func confirmReplacement() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string(.settingsCLIReplaceTitle)
        alert.informativeText = L10n.format(
            .settingsCLIReplaceMessage,
            installationURL.path
        )
        alert.addButton(withTitle: L10n.string(.settingsCLIReplace))
        alert.addButton(withTitle: L10n.string(.commonCancel))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func report(_ error: Error) {
        errorMessage = L10n.format(.settingsCLIOperationFailed, error.localizedDescription)
        refreshInstallationStatus()
    }

    private static func executeWithAdministratorPrivileges(
        _ operation: CommandLineToolOperation
    ) throws {
        let shellCommand = privilegedShellCommand(for: operation)
        let appleScriptSource = "do shell script \"\(appleScriptLiteral(shellCommand))\" "
            + "with administrator privileges"
        guard let script = NSAppleScript(source: appleScriptSource) else {
            throw CommandLineToolInstallerError.privilegedOperation(
                L10n.string(.settingsCLIPrivilegedOperationFailed)
            )
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            if number == -128 {
                throw CommandLineToolInstallerError.authorizationCancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? L10n.string(.settingsCLIPrivilegedOperationFailed)
            throw CommandLineToolInstallerError.privilegedOperation(message)
        }
    }

    nonisolated static func privilegedShellCommand(
        for operation: CommandLineToolOperation
    ) -> String {
        let sourceURL: URL
        let targetURL: URL
        let replacingExisting: Bool
        let isUninstall: Bool
        switch operation {
        case .install(let source, let target, let replacing):
            sourceURL = source
            targetURL = target
            replacingExisting = replacing
            isUninstall = false
        case .uninstall(let source, let target):
            sourceURL = source
            targetURL = target
            replacingExisting = false
            isUninstall = true
        }

        let source = encodedPath(sourceURL)
        let target = encodedPath(targetURL)
        let directory = encodedPath(targetURL.deletingLastPathComponent())
        var commands = [
            "set -eu",
            "source_path=$(/usr/bin/printf %s \(source) | /usr/bin/base64 -D)",
            "target_path=$(/usr/bin/printf %s \(target) | /usr/bin/base64 -D)",
            "directory_path=$(/usr/bin/printf %s \(directory) | /usr/bin/base64 -D)",
            "[ -x \"$source_path\" ] || exit 76"
        ]

        if isUninstall {
            commands.append(
                "if [ ! -L \"$target_path\" ]; then exit 74; fi"
            )
            commands.append(
                "if [ \"$(/usr/bin/readlink \"$target_path\")\" != \"$source_path\" ]; "
                    + "then exit 74; fi"
            )
            commands.append("/bin/rm -f \"$target_path\"")
        } else {
            commands.append("/bin/mkdir -p \"$directory_path\"")
            commands.append(
                "if [ -d \"$target_path\" ] && [ ! -L \"$target_path\" ]; "
                    + "then exit 73; fi"
            )
            if replacingExisting {
                commands.append(
                    "if [ -e \"$target_path\" ] || [ -L \"$target_path\" ]; "
                        + "then /bin/rm -f \"$target_path\"; fi"
                )
            } else {
                commands.append(
                    "if [ -e \"$target_path\" ] || [ -L \"$target_path\" ]; "
                        + "then exit 75; fi"
                )
            }
            commands.append("/bin/ln -s \"$source_path\" \"$target_path\"")
        }
        return commands.joined(separator: "; ")
    }

    nonisolated private static func encodedPath(_ url: URL) -> String {
        Data(url.standardizedFileURL.path.utf8).base64EncodedString()
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
