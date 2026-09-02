import AppKit
import Combine
import Foundation

enum CommandLineToolInstallerError: LocalizedError, Equatable {
    case bundledToolMissing
    case bundledInstallerMissing
    case temporaryApplicationLocation
    case targetIsDirectory
    case installationChanged
    case helperLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledToolMissing:
            L10n.string(.settingsCLIMissingTool)
        case .bundledInstallerMissing:
            L10n.string(.settingsCLIMissingInstaller)
        case .temporaryApplicationLocation:
            L10n.string(.settingsCLITemporaryApp)
        case .targetIsDirectory:
            L10n.string(.settingsCLITargetDirectory)
        case .installationChanged:
            L10n.string(.settingsCLIInstallationChanged)
        case .helperLaunchFailed(let message):
            L10n.format(.settingsCLIHelperLaunchFailed, message)
        }
    }
}

enum CommandLineToolOperation: Equatable {
    case install
    case uninstall

    var helperBundleName: String {
        switch self {
        case .install:
            "MoDuCLIInstall.app"
        case .uninstall:
            "MoDuCLIUninstall.app"
        }
    }
}

typealias CommandLineToolOperationCompletion = @MainActor (Result<Void, Error>) -> Void
typealias CommandLineToolOperationPerformer = (
    CommandLineToolOperation,
    @escaping CommandLineToolOperationCompletion
) throws -> Void

@MainActor
final class CommandLineToolInstaller: ObservableObject {
    nonisolated static let systemInstallationURL = URL(
        fileURLWithPath: "/usr/local/bin/modu"
    )

    @Published private(set) var installedURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPerformingOperation = false

    private let fileManager: FileManager
    private let bundledToolURL: URL
    private let applicationURL: URL
    private let installationURL: URL
    private let performOperation: CommandLineToolOperationPerformer

    init(
        fileManager: FileManager = .default,
        applicationURL: URL = Bundle.main.bundleURL,
        bundledToolURL: URL? = nil,
        installationURL: URL = CommandLineToolInstaller.systemInstallationURL,
        performOperation: CommandLineToolOperationPerformer? = nil
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

        if let performOperation {
            self.performOperation = performOperation
        } else {
            let helpersURL = applicationURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .standardizedFileURL
            self.performOperation = { operation, completion in
                try Self.launchInstallerHelper(
                    at: helpersURL.appendingPathComponent(
                        operation.helperBundleName,
                        isDirectory: true
                    ),
                    completion: completion
                )
            }
        }
        refreshInstallationStatus()
    }

    var isInstalled: Bool { installedURL != nil }

    func installFromSettings() {
        errorMessage = nil
        do {
            try install()
        } catch {
            report(error)
        }
    }

    func uninstallFromSettings() {
        errorMessage = nil
        do {
            try uninstall()
        } catch {
            report(error)
        }
    }

    func install() throws {
        guard !isPerformingOperation else { return }
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
        }

        try begin(.install)
    }

    func uninstall() throws {
        guard !isPerformingOperation else { return }
        guard isCurrentInstallation else {
            refreshInstallationStatus()
            throw CommandLineToolInstallerError.installationChanged
        }
        try begin(.uninstall)
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

    private func begin(_ operation: CommandLineToolOperation) throws {
        isPerformingOperation = true
        do {
            try performOperation(operation) { [weak self] result in
                guard let self else { return }
                self.isPerformingOperation = false
                self.refreshInstallationStatus()
                switch result {
                case .success:
                    self.errorMessage = nil
                case .failure(let error):
                    self.report(error)
                }
            }
        } catch {
            isPerformingOperation = false
            throw error
        }
    }

    private func report(_ error: Error) {
        errorMessage = L10n.format(.settingsCLIOperationFailed, error.localizedDescription)
        refreshInstallationStatus()
    }

    private static func launchInstallerHelper(
        at helperURL: URL,
        completion: @escaping CommandLineToolOperationCompletion
    ) throws {
        let executableURL = helperURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("MoDuCLIInstaller")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CommandLineToolInstallerError.bundledInstallerMissing
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false

        NSWorkspace.shared.openApplication(
            at: helperURL,
            configuration: configuration
        ) { runningApplication, error in
            Task { @MainActor in
                if let error {
                    completion(
                        .failure(
                            CommandLineToolInstallerError.helperLaunchFailed(
                                error.localizedDescription
                            )
                        )
                    )
                    return
                }
                guard let runningApplication else {
                    completion(
                        .failure(
                            CommandLineToolInstallerError.helperLaunchFailed(
                                L10n.string(.commonUnknownError)
                            )
                        )
                    )
                    return
                }

                while !runningApplication.isTerminated {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                completion(.success(()))
            }
        }
    }
}
