import AppKit
import Darwin
import Foundation

enum CLIInstallerOperation: String, CaseIterable {
    case install
    case replace
    case uninstall
}

enum CLIInstallerCommand {
    static let targetURL = URL(fileURLWithPath: "/usr/local/bin/modu")

    static func authorizationPrompt(
        for operation: CLIInstallerOperation,
        isChinese: Bool
    ) -> String {
        switch operation {
        case .install, .replace:
            return isChinese
                ? "将 modu 命令安装到 /usr/local/bin 需要管理员权限。"
                : "Administrator permission is required to install the modu command at /usr/local/bin."
        case .uninstall:
            return isChinese
                ? "从 /usr/local/bin 卸载 modu 命令需要管理员权限。"
                : "Administrator permission is required to remove the modu command from /usr/local/bin."
        }
    }

    static func privilegedShellCommand(
        for operation: CLIInstallerOperation,
        sourceURL: URL,
        targetURL: URL = CLIInstallerCommand.targetURL
    ) -> String {
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

        switch operation {
        case .uninstall:
            commands.append("if [ ! -L \"$target_path\" ]; then exit 74; fi")
            commands.append(
                "if [ \"$(/usr/bin/readlink \"$target_path\")\" != \"$source_path\" ]; "
                    + "then exit 74; fi"
            )
            commands.append("/bin/rm -f \"$target_path\"")
        case .install, .replace:
            commands.append("/bin/mkdir -p \"$directory_path\"")
            commands.append(
                "if [ -d \"$target_path\" ] && [ ! -L \"$target_path\" ]; "
                    + "then exit 73; fi"
            )
            if operation == .replace {
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

    private static func encodedPath(_ url: URL) -> String {
        Data(url.standardizedFileURL.path.utf8).base64EncodedString()
    }
}

private struct InstallerFailure: Error {
    let number: Int?
    let message: String
}

@main
struct MoDuCLIInstaller {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let language = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        let isChinese = language.lowercased().hasPrefix("zh")

        do {
            guard
                let rawOperation = Bundle.main.object(
                    forInfoDictionaryKey: "MoDuCLIInstallerOperation"
                ) as? String,
                let requestedOperation = CLIInstallerOperation(rawValue: rawOperation),
                requestedOperation != .replace
            else {
                throw InstallerFailure(
                    number: nil,
                    message: localized(
                        isChinese,
                        chinese: "安装助手收到的操作无效。",
                        english: "The installer received an invalid operation."
                    )
                )
            }

            let sourceURL = try bundledLauncherURL()
            guard let operation = try resolvedOperation(
                requestedOperation,
                sourceURL: sourceURL,
                isChinese: isChinese
            ) else {
                exit(EXIT_SUCCESS)
            }
            try runAuthorizedCommand(
                CLIInstallerCommand.privilegedShellCommand(
                    for: operation,
                    sourceURL: sourceURL
                ),
                prompt: CLIInstallerCommand.authorizationPrompt(
                    for: operation,
                    isChinese: isChinese
                )
            )
        } catch let failure as InstallerFailure where failure.number == -128 {
            exit(EXIT_SUCCESS)
        } catch {
            applicationActivate()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = localized(
                isChinese,
                chinese: "无法完成命令行工具操作",
                english: "Could Not Complete Command Line Tool Operation"
            )
            if let failure = error as? InstallerFailure {
                alert.informativeText = localizedMessage(for: failure, isChinese: isChinese)
            } else {
                alert.informativeText = error.localizedDescription
            }
            alert.runModal()
            exit(EXIT_FAILURE)
        }

        exit(EXIT_SUCCESS)
    }

    private static func resolvedOperation(
        _ requestedOperation: CLIInstallerOperation,
        sourceURL: URL,
        isChinese: Bool
    ) throws -> CLIInstallerOperation? {
        let targetURL = CLIInstallerCommand.targetURL
        let fileManager = FileManager.default

        if requestedOperation == .uninstall {
            guard isCurrentInstallation(sourceURL: sourceURL, targetURL: targetURL) else {
                throw InstallerFailure(
                    number: 74,
                    message: "The modu installation changed."
                )
            }
            return .uninstall
        }

        if isCurrentInstallation(sourceURL: sourceURL, targetURL: targetURL) {
            return nil
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: targetURL.path,
            isDirectory: &isDirectory
        ) || isSymbolicLink(at: targetURL)
        if exists, isDirectory.boolValue, !isSymbolicLink(at: targetURL) {
            throw InstallerFailure(
                number: 73,
                message: "The modu target is a directory."
            )
        }
        guard exists else { return .install }

        applicationActivate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localized(
            isChinese,
            chinese: "替换现有的 modu？",
            english: "Replace Existing modu?"
        )
        alert.informativeText = localized(
            isChinese,
            chinese: "/usr/local/bin 中已经存在名为 modu 的项目。是否将它替换为 MoDu 命令？",
            english: "/usr/local/bin already contains an item named modu. Replace it with the MoDu command?"
        )
        alert.addButton(
            withTitle: localized(isChinese, chinese: "替换", english: "Replace")
        )
        alert.addButton(
            withTitle: localized(isChinese, chinese: "取消", english: "Cancel")
        )
        return alert.runModal() == .alertFirstButtonReturn ? .replace : nil
    }

    private static func isCurrentInstallation(sourceURL: URL, targetURL: URL) -> Bool {
        guard
            let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: targetURL.path
            )
        else {
            return false
        }
        let destinationURL = URL(
            fileURLWithPath: destination,
            relativeTo: targetURL.deletingLastPathComponent()
        ).resolvingSymlinksInPath().standardizedFileURL
        return destinationURL == sourceURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isSymbolicLink(at url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func applicationActivate() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static func bundledLauncherURL() throws -> URL {
        let helperBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let helpersURL = helperBundleURL.deletingLastPathComponent()
        let contentsURL = helpersURL.deletingLastPathComponent()
        let applicationURL = contentsURL.deletingLastPathComponent().standardizedFileURL
        guard
            helpersURL.lastPathComponent == "Helpers",
            contentsURL.lastPathComponent == "Contents",
            applicationURL.pathExtension == "app"
        else {
            throw InstallerFailure(
                number: nil,
                message: "The installer is not inside a valid MoDu application bundle."
            )
        }

        let applicationPath = applicationURL.resolvingSymlinksInPath().path
        guard
            !applicationPath.hasPrefix("/Volumes/"),
            !applicationPath.contains("/AppTranslocation/")
        else {
            throw InstallerFailure(
                number: nil,
                message: "Move MoDu out of the disk image before installing its command line tool."
            )
        }

        let launcherURL = applicationURL
            .appendingPathComponent("Contents/Resources/CLI", isDirectory: true)
            .appendingPathComponent("modu")
            .standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            throw InstallerFailure(
                number: 76,
                message: "The bundled command line launcher is missing."
            )
        }
        return launcherURL
    }

    private static func runAuthorizedCommand(
        _ shellCommand: String,
        prompt: String
    ) throws {
        let source = "do shell script \"\(appleScriptLiteral(shellCommand))\" "
            + "with administrator privileges "
            + "with prompt \"\(appleScriptLiteral(prompt))\""
        guard let script = NSAppleScript(source: source) else {
            throw InstallerFailure(number: nil, message: "Could not create the authorization request.")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw InstallerFailure(
                number: errorInfo[NSAppleScript.errorNumber] as? Int,
                message: errorInfo[NSAppleScript.errorMessage] as? String
                    ?? "The system authorization operation failed."
            )
        }
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func localizedMessage(
        for failure: InstallerFailure,
        isChinese: Bool
    ) -> String {
        switch failure.number {
        case 73:
            localized(
                isChinese,
                chinese: "/usr/local/bin 中存在名为 modu 的文件夹，墨读不会替换它。",
                english: "/usr/local/bin contains a folder named modu, which MoDu will not replace."
            )
        case 74:
            localized(
                isChinese,
                chinese: "modu 的安装状态已经变化，请返回设置后重试。",
                english: "The modu installation changed. Return to Settings and try again."
            )
        case 75:
            localized(
                isChinese,
                chinese: "/usr/local/bin 中已经存在名为 modu 的项目。",
                english: "/usr/local/bin already contains an item named modu."
            )
        case 76:
            localized(
                isChinese,
                chinese: "应用内置的命令行启动器不存在。",
                english: "The bundled command line launcher is missing."
            )
        default:
            failure.message
        }
    }

    private static func localized(
        _ isChinese: Bool,
        chinese: String,
        english: String
    ) -> String {
        isChinese ? chinese : english
    }
}
